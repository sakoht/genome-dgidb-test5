package Genome::Model::Tools::Lims::ImportSangerRun;

use strict;
use warnings;

use Genome;

use Regexp::Common;

class Genome::Model::Tools::Lims::ImportSangerRun {
    is => 'Command::V2',
    has => [
        run_names => {
            is => 'Text',
            is_many => 1,
            shell_args_position => 1,
            doc => 'The run name',
        },
    ],
};

sub help_brief {
    return 'Import a sanger run into genome';
}

sub execute {
    my $self = shift;
    $self->status_message('Import sanger instrument data...');

    my ($att, $succ) = (qw/ 0 0 /);
    for my $run_name ( $self->run_names ) {
        $att++;
        $succ++ if $self->_import_run($run_name);
    }

    $self->status_message('Attempted: '.$att);
    $self->status_message('Success: '.$succ);
    return $succ;
}

sub _import_run {
    my ($self, $run_name) = @_;
    $self->status_message("Run name: $run_name");

    my $sanger = Genome::InstrumentData::Sanger->get($run_name);
    my $created = 0;
    if ( not $sanger ) {
        $sanger = Genome::InstrumentData::Sanger->create(
            id => $run_name,
            run_name => $run_name,
        );
        if ( not $sanger ) {
            $self->error_message('Failed to create sanger intrument data for run name: '.$run_name);
            return;
        }
        $created = 1;
    }
    $self->status_message('Run name: '.$sanger->id);

    my $library_ids = $self->_dump_to_file_system($sanger);
    if ( not $library_ids ) {
        $self->error_message('Failed to dump lims sanger reads to file system!');
        $sanger->delete if $created;
        return;
    }

    my $library = $self->_set_unique_read_library($sanger, $library_ids);
    if ( not $library ) {
        $sanger->delete if $created;
        return;
    };

    return 1;
}

sub _dump_to_file_system {
    my ($self, $sanger) = @_;
    $self->status_message('Dump reads to file system...');

    my $disk_allocation = $sanger->disk_allocation;
    unless ( $disk_allocation ) {
        $disk_allocation = Genome::Disk::Allocation->allocate(
            disk_group_name => 'info_alignments',
            allocation_path => '/instrument_data/sanger'.$sanger->id,
            kilobytes_requested => 10240, # 10 Mb
            owner_class_name => $sanger->class,
            owner_id => $sanger->id
        );
        unless ($disk_allocation) {
            $self->error_message('Failed to create disk allocation for sanger instrument data '.$sanger->id);
            return;
        }
    }
    $self->status_message('Allocation: '.$disk_allocation->id);

    my $data_dir = $disk_allocation->absolute_path;
    unless ( Genome::Sys->validate_existing_directory($data_dir) ) {
        $self->error_message('Absolute path from disk allocation does not exist for sanger instrument data '.$sanger->id);
        return;
    }
    $self->status_message('Directory: '.$data_dir);

    my $reads = App::DB::TableRow::Iterator->new(
        class => 'GSC::Sequence::Read',
        params => {
            prep_group_id => $sanger->run_name,
        },
    );
    unless ( $reads ) {
        $self->error_message( sprintf('Could not make read iterartor for run name (%s)', $sanger->run_name) );
        return;
    }

    $self->status_message('Go through read iterator...');
    my $read_cnt = 0;
    my %library_ids;
    while ( my $read = $reads->next ) {
        $library_ids{$read->library_id}++ if $read->library_id;
        $read_cnt++;
        my $scf_name = $read->default_file_name('scf');
        my $scf_file = sprintf('%s/%s.gz', $data_dir, $scf_name);
        my $size = -s $scf_file;
        next if $size and $size > 1000; # if small retry dump
        unlink $scf_file if -e $scf_file; 
        my $scf_fh = IO::File->new($scf_file, 'w');
        unless ( $scf_fh ) {
            $self->error_message("Can't open scf ($scf_file)\n$!");
            return;
        }
        $scf_fh->print( Compress::Zlib::memGzip($read->scf_content) );
        $scf_fh->close;
        $self->error_message("No scf content for $scf_name") unless -s $scf_file;
    }

    unless ( $read_cnt ) {
        $self->error_message("No reads found for run ".$sanger->run_name);
        return;
    }

    $self->status_message("Read count: $read_cnt");
    $self->status_message("Dump reads to file system...OK");
    return \%library_ids;
}

sub _set_unique_read_library {
    my ($self, $sanger, $library_ids) = @_;

    my @library_ids = grep { $_ =~ /^$RE{num}{int}$/ }  keys %$library_ids;
    $self->status_message('Found '.@library_ids.' libraries');
    $self->status_message('Using library id: '.$library_ids[0]);
    my $library = Genome::Library->get(id => $library_ids[0]);
    if ( not $library ) {
        $self->error_message('Failed to get library for id: '.$library_ids[0]);
        return;
    }
    $sanger->library($library) if not $sanger->library;

    return $library;
}

1;

