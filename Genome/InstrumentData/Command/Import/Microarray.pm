package Genome::InstrumentData::Command::Import::Microarray;

use strict;
use warnings;

use Genome;
use File::Copy;
use File::Path;
use File::Copy::Recursive;
use File::Basename;
use IO::Handle;

my %properties = (
    original_data_path => {
        is => 'Text',
        doc => 'original data path of import data file(s): all files in path will be used as input',
    },
    sample_name => {
        is => 'Text',
        doc => 'sample name for imported file, like TCGA-06-0188-10B-01D',
    },
    import_source_name => {
        is => 'Text',
        doc => 'source name for imported file, like Broad Institute',
        is_optional => 1,
    },
    import_format => {
        is => 'Text',
        doc => 'format of import data, like microarray',
        valid_values => ['unknown'],                
        is_optional => 1,
    },
    sequencing_platform => {
        is => 'Text',
        doc => 'sequencing platform of import data, like illumina/affymetrix',
        valid_values => ['illumina genotype array', 'illumina expression array', 'affymetrix genotype array', '454','sanger','unknown'],
        is_optional => 1,
    },
    description  => {
        is => 'Text',
        doc => 'general description of import data, like which software maq/bwa/bowtie to used to generate this data',
        is_optional => 1,
    },
    allocation => {
        is => 'Genome::Disk::Allocation',
        is_optional => 1,
        reverse_as => 'owner', where => [ allocation_path => {operator => 'like', value => '%imported%'} ], is_optional => 1, is_many => 1, 

    },
    species_name => {
        is => 'Text',
        doc => 'this is only needed if the sample being used is not already in the database.',
        is_optional => 1,
    },
);
    
class Genome::InstrumentData::Command::Import::Microarray {
    is => 'Command',
    is_abstract => 1,
    has => [%properties],
    doc => 'import external microarray instrument data',
};

sub execute {
    my $self = shift;
    $self->process_imported_files;
}

sub process_imported_files {
    my ($self,$sample_name) = @_;
    unless (-s $self->original_data_path) {
        $self->error_message('Original data path of import file: '. $self->original_data_path .' is empty');
        return;
    }
    my %params = ();
    for my $property_name (keys %properties) {
        unless ($properties{$property_name}->{is_optional}) {
            unless ($self->$property_name) {
                $self->error_message ("Required property: $property_name is not given");
                return;
            }
        }
        next if $property_name =~ /^(species|reference)_name$/;
        next if $property_name eq "allocation";
        $params{$property_name} = $self->$property_name if defined($self->$property_name);
    }

    $sample_name = $self->sample_name;
    my $genome_sample = Genome::Sample->get(name => $sample_name);

    if ($genome_sample) {
        $self->status_message("Sample with full_name: $sample_name is found in database");
    }
    else {
        $genome_sample = Genome::Sample->get(extraction_label => $sample_name);
        $self->status_message("Sample with sample_name: $sample_name is found in database")
            if $genome_sample;
    }

    unless ($genome_sample) {
        $self->error_message("Could not find sample by the name of: ".$sample_name.". To continue, add the sample and rerun.");
        die $self->error_message;
    }
    
    my $sample_id = $genome_sample->id;
    $self->status_message("genome sample $sample_name has id: $sample_id");
    $params{sample_id} = $sample_id;
    $params{import_format} = "unknown";
    if($self->allocation) {
        $params{disk_allocations} = $self->allocation;
    }

    my $import_instrument_data = Genome::InstrumentData::Imported->create(%params); 

    unless ($import_instrument_data) {
       $self->error_message('Failed to create imported instrument data for '.$self->original_data_path);
       return;
    }

    my $instrument_data_id = $import_instrument_data->id;
    $self->status_message("Instrument data record $instrument_data_id has been created.");
    print "Intrument data:".$instrument_data_id." is imported.\n";
    my $kb_usage = $import_instrument_data->calculate_alignment_estimated_kb_usage * 5;

    my $alloc_path = sprintf('microarray_data/imported/%s', $instrument_data_id);

    my %alloc_params = (
        disk_group_name     => 'info_alignments',
        allocation_path     => $alloc_path,
        kilobytes_requested => $kb_usage * 5,
        owner_class_name    => $import_instrument_data->class,
        owner_id            => $import_instrument_data->id,
    );

    my $disk_alloc = $import_instrument_data->disk_allocations;

    unless($disk_alloc) {
        print "Allocating disk space\n";
        $self->status_message("Allocating disk space");
        $disk_alloc = Genome::Disk::Allocation->allocate(%alloc_params); 
    }
    unless ($disk_alloc) {
        $self->error_message("Failed to get disk allocation with params:\n". Data::Dumper::Dumper(%alloc_params));
        die $self->error_message;
    }
    $self->status_message("Microarray allocation created for $instrument_data_id.");

    my $target_path = $disk_alloc->absolute_path;# . "/";
    $self->status_message("Microarray allocation created at $target_path .");
    print "attempting to copy data to allocation\n";
    my $status = File::Copy::Recursive::dircopy($self->original_data_path,$target_path);
    unless($status) {
        $self->error_message("Directory copy failed to complete.\n");
        return;
    }

    my $ssize = Genome::Utility::FileSystem->directory_size_recursive($self->original_data_path);             
    my $dsize = Genome::Utility::FileSystem->directory_size_recursive($target_path);             
    unless ($ssize==$dsize) {
        unless($import_instrument_data->id < 0) {
            $self->error_message("source and distination do not match( source $ssize bytes vs destination $dsize). Copy failed.");
            $self->status_messsage("Removing failed copy");
            print $self->status_message."\n";
            rmtree($target_path);
            $disk_alloc->deallocate;
            return;
        }
    }
    
    $self->status_message("Finished copying data into the allocated disk");
    print "Finished copying data into the allocated disk.\n";

    return 1;
}

1;

#$HeadURL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/Genome/InstrumentData/Command/Import.pm $
#$Id: Import.pm 53285 2009-11-20 21:28:55Z fdu $
