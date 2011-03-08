package Genome::SoftwareResult::Stageable;

use warnings;
use strict;
use Genome;
use Sys::Hostname;

class Genome::SoftwareResult::Stageable {
    is => 'Genome::SoftwareResult',
    is_abstract => 1,
    has_transient => [
        temp_staging_directory => {
                        is => 'Text',
                        doc => 'Directory to use for staging the generated data before putting on allocated disk.',
                        is_optional => 1
        }

    ]
};

sub resolve_allocation_subdirectory {
    die "Must define resolve_allocation_subdirectory in your subclass of Genome::SoftwareResult::Stageable";
}

sub resolve_allocation_disk_group_name {
    die "Must define resolve_allocation_disk_group_name in your subclass of Genome::SoftwareResult::Stageable";
}

sub _working_dir_prefix {
    "software-result";
}

sub _prepare_staging_directory {
    my $self = shift;

    return $self->temp_staging_directory if ($self->temp_staging_directory);

    my $base_temp_dir = Genome::Sys->base_temp_directory();

    my $hostname = hostname;
    my $user = $ENV{'USER'};
    my $basedir = sprintf("%s-%s-%s-%s-%s", $self->_working_dir_prefix, $hostname, $user, $$, $self->id);
    my $tempdir = Genome::Sys->create_temp_directory($basedir);
    unless($tempdir) {
        die "failed to create a temp staging directory for completed files";
    }
    $self->temp_staging_directory($tempdir);


    return 1;
}

sub _prepare_output_directory {
    my $self = shift;

    my $subdir = $self->resolve_allocation_subdirectory;
    unless ($subdir) {
        $self->error_message("failed to resolve subdirectory for output data.  cannot proceed.");
        die $self->error_message;
    }
    
    my %allocation_get_parameters = (
        disk_group_name => $self->resolve_allocation_disk_group_name,
        allocation_path => $subdir,
    );

    my %allocation_create_parameters = (
        %allocation_get_parameters,
        kilobytes_requested => $self->_staging_disk_usage,
        owner_class_name => $self->class,
        owner_id => $self->id
    );
    
    my $allocation = Genome::Disk::Allocation->allocate(%allocation_create_parameters);
    unless ($allocation) {
        $self->error_message("Failed to get disk allocation with params:\n". Dumper(%allocation_create_parameters));
        die($self->error_message);
    }

    my $output_dir = $allocation->absolute_path;
    unless (-d $output_dir) {
        $self->error_message("Allocation path $output_dir doesn't exist!");
        die $self->error_message;
    }
    
    $self->output_dir($output_dir);
    
    return $output_dir;
}

sub _staging_disk_usage {

    my $self = shift;
    my $usage;
    unless ($usage = Genome::Sys->disk_usage_for_path($self->temp_staging_directory)) {
        $self->error_message("Failed to get disk usage for staging: " . Genome::Sys->error_message);
        die $self->error_message;
    }

    return $usage;
}

sub _needs_symlinks_followed_when_syncing {
    return 0;
}


sub _promote_data {
    my $self = shift;

    #my $container_dir = File::Basename::dirname($self->output_dir);
    my $staging_dir = $self->temp_staging_directory;
    my $output_dir  = $self->output_dir;

    $self->status_message("Now de-staging data from $staging_dir into $output_dir"); 

    my $rsync_params = "-avz";
    $rsync_params .= "L" if ($self->_needs_symlinks_followed_when_syncing);

    my $call = sprintf("rsync %s %s/* %s", $rsync_params, $staging_dir, $output_dir);

    my $rv = system($call);
    $self->status_message("Running Rsync: $call");

    unless ($rv == 0) {
        $self->error_message("Did not get a valid return from rsync, rv was $rv for call $call.  Cleaning up and bailing out");
        rmpath($output_dir);
        die $self->error_message;
    }

    chmod 02775, $output_dir;
    for my $subdir (grep { -d $_  } glob("$output_dir/*")) {
        chmod 02775, $subdir;
    }
   
    # Make everything in here read-only 
    for my $file (grep { -f $_  } glob("$output_dir/*")) {
        chmod 0444, $file;
    }

    $self->status_message("Files in $output_dir: \n" . join "\n", glob($output_dir . "/*"));

    return $output_dir;
}

1;
