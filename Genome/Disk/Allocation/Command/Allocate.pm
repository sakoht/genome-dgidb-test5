package Genome::Disk::Allocation::Command::Allocate;

use strict;
use warnings;

use Genome;

class Genome::Disk::Allocation::Command::Allocate {
    is => 'Genome::Disk::Allocation::Command',
    has => [
            allocation_path => {
                                is => 'Text',
                                doc => 'The sub-dir of the disk volume for which space is allocated',
                            },
            kilobytes_requested => {
                                    is => 'Number',
                                    doc => 'The disk space allocated in kilobytes',
                                },
            owner_class_name => {
                                 is => 'Text',
                                 doc => 'The class name for the owner of this allocation',
                             },
            owner_id => {
                         is => 'Number',
                         doc => 'The id for the owner of this allocation',
                     },
        ],
    has_optional => [
                     mount_path => {
                                    is => 'Text',
                                    doc => 'The mount path of the disk volume',
                                },
                     kilobytes_used => {
                                        is => 'Number',
                                        doc => 'The actual disk space used by owner',
                                    },
              ],
    doc => 'An allocate command to create and confirm GSC::PSE::AllocateDiskSpace and GSC::DiskAllocation',
};

sub create {
    my $class = shift;

    my %params = @_;
    my $self = $class->SUPER::create(%params);
    unless ($self) {
        return;
    }
    if ($self->mount_path) {
        my @mps = $self->_get_all_mount_paths;
        unless (grep {$_ eq $self->mount_path} @mps) {
            my $error_message = "Disk mount path '". $self->mount_path
                ."' is not an available disk mount path.  Choose one of the following:\n";
            $error_message .= join("\n",@mps);
            $self->error_message($error_message);
            $self->delete;
            return;
        }
    }
    my $owner_class_name = $self->owner_class_name;
    unless ($owner_class_name) {
        $self->error_message('Owner class name is required!  See --help.');
        $self->delete;
        return;
    }
    my $owner_id = $self->owner_id;
    unless ($owner_id) {
        $self->error_message('Owner id is required!  See --help.');
        $self->delete;
        return;
    }
    
    # TODO: this would be nice but we have to fork to commit the allocate PSE
    #my $owner_object = $owner_class_name->get($owner_id);
    #unless ($owner_object) {
    #    $self->error_message('Failed to get object of class '.
    #                         $owner_class_name .' and id '. $owner_id);
    #    $self->delete;
    #    return;
    #}

    unless ($self->allocation_path) {
        $self->error_message('Allocation path is required! See --help.');
        $self->delete;
        return;
    }
    unless ($self->verify_no_parent_allocation($self->allocation_path)) {
        $self->error_message('Parent allocation found for path '. $self->allocation_path);
        $self->delete;
        return;
    }

    unless ($self->kilobytes_requested) {
        $self->error_message('Kilobytes requested is required! See --help.');
        $self->delete;
        return;
    }

    my $disk_volume;
    if ($self->mount_path) {
        ($disk_volume) = $self->get_disk_volumes;
    }
    unless ($self->allocator_id) {
        my %pse_params = (
                          process_to => 'allocate disk space',
                          disk_group_name => $self->disk_group_name,
                          space_needed => $self->kilobytes_requested,
                          allocation_path => $self->allocation_path,
                          owner_class_name => $self->owner_class_name,
                          owner_id => $self->owner_id,
                          control_pse_id => '1',
                      );
        if ($disk_volume) {
            $pse_params{dv_id} = $disk_volume->dv_id;
        }
        my $allocator = GSC::ProcessStep->schedule(%pse_params);
        unless ($allocator) {
            $self->error_message('Failed to schedule allocate PSE.');
            $self->delete;
            return;
        }
        $self->allocator_id($allocator->pse_id);
    }
    unless ($self->allocator) {
        $self->error_message('Allocator not found for allocator id '. $self->allocator_id);
        $self->delete;
        return;
    }
    return $self;
}

sub execute {
    my $self = shift;

    my $allocator = $self->allocator;

    $self->status_message('Confirming allocate PSE id: '. $self->allocator_id);

    my $user_name = (getpwuid($<))[0];

    my $old_dbi_trace_level;
    my $trace_fh;

    if ($user_name eq 'mjohnson') {
       
        $old_dbi_trace_level = DBI->trace();
        
        $trace_fh = File::Temp->new(
                                    'TEMPLATE' => 'allocation_pse_wrapper_XXXXXXXXXX',
                                    'DIR'      => '/gsc/var/log/genome/allocation_debugging',
                                    'SUFFIX'   => '.tmp',
                                   );
                                   
        $trace_fh->autoflush(1);
    
        DBI->trace(4, $trace_fh);
    
    }
    
    my $rv;
    if ($self->local_confirm) {
        $rv = $self->confirm_scheduled_pse($allocator);
    } else {
        $rv = $self->wait_for_pse_to_confirm(pse => $allocator);
    }

    # Commit here to free up a DB lock we'll be holding if we executed the 
    # allocation PSE via confirm_scheduled_pse().  If we block on a hung
    # mount below when we start check / create the directory. 
    UR::Context->commit();

    if (defined($old_dbi_trace_level)) {
        DBI->trace($old_dbi_trace_level, undef);
    }
   
    if (defined($trace_fh)) {
        $trace_fh->close();
    }
    
    unless ($rv) {
        $self->error_message('Failed to confirm pse '. $self->allocator_id);
        return;
    }

    my $gsc_disk_allocation = $self->gsc_disk_allocation;
    unless ($gsc_disk_allocation) {
        $self->error_message('Failed to get GSC::DiskAllocation for alloction '. $self->allocator_id);
        return;
    }
    my %params;
    my $gsc_disk_allocation_class_object = $gsc_disk_allocation->get_class_object;
    for my $property ($gsc_disk_allocation_class_object->all_property_names) {
        $params{$property} = $gsc_disk_allocation->$property;
    }
    my $defined_allocation = Genome::Disk::Allocation->__define__(%params);
    unless ($defined_allocation) {
        $self->error_message('Failed to define a Genome::Disk::Allocation for: '. Data::Dumper::Dumper(%params));
        return;
    }
    my $disk_allocation = $self->disk_allocation;
    unless ($disk_allocation) {
        $self->error_message('Failed to get Genome::Disk::Allocation for allocator_id '. $self->allocator_id);
        return;
    }
    my $path = $disk_allocation->absolute_path;
    unless (-e $path) {
        Genome::Utility::FileSystem->create_directory($path);        
        unless (-e $path) {
            die $self->error_message("Failed to create directory $path! $!");
        }
    }
    return 1;
}

sub verify_no_parent_allocation {
    my $self = shift;
    my $path = shift;

    my ($allocation) = Genome::Disk::Allocation->get(allocation_path => $path);
    if ($allocation) {
        return;
    }
    my $dir = File::Basename::dirname($path);
    if ($dir ne '.' && $dir ne '/') {
        return $self->verify_no_parent_allocation($dir);
    }
    return 1;
}

1;
