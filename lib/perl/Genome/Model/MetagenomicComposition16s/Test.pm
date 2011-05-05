package Genome::Model::MetagenomicComposition16s::Test;

use strict;
use warnings;

require Carp;
use Data::Dumper 'Dumper';
require Genome::Model::Test;
use Test::More;

BEGIN {
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
}

#< Dirs >#
sub _base_directory {
    my ($class, $sequencing_platform) = @_;
    Carp::confess('No sequencing platform given to get base directory') if not $sequencing_platform;
    my $dir = '/gsc/var/cache/testsuite/data/Genome-Model/MetagenomicComposition16s';
    $dir .= ucfirst $sequencing_platform;
    Carp::confess("Base directory ($dir) for sequencing platform ($sequencing_platform) does not exist.") unless -d $dir;
    return $dir;
}

sub _example_directory_for_model {
    my ($class, $model) = @_;
    Carp::confess('No model to get example dir') if not $model;
    my $dir = $class->_base_directory($model->processing_profile->sequencing_platform);
    $dir .= '/build';
    Carp::confess("Example directory ($dir) for mc16s model does not exist.") unless -d $dir;
    return $dir;
}

sub _instrument_data_dir_for_sequencing_platform {
    my ($class, $sequencing_platform) = @_;
    my $dir = '/gsc/var/cache/testsuite/data/Genome-Model/MetagenomicComposition16s'.
    ucfirst($sequencing_platform).'/inst_data';
    Carp::confess("Instrument data directory ($dir) for mc16s model does not exist.") unless -d $dir;
    return $dir;
}
#<>#

#< Library Sample Taxon >#
our($taxon, $sample, $library);
sub _taxon_sample_and_library {
    my $self = shift; 

    $taxon = Genome::Taxon->create(
        name => 'Human Metagenome TEST',
        domain => 'Unknown',
        current_default_org_prefix => undef,
        estimated_genome_size => undef,
        current_genome_refseq_id => undef,
        ncbi_taxon_id => undef,
        ncbi_taxon_species_name => undef,
        species_latin_name => 'Human Metagenome',
        strain_name => 'TEST',
    );
    if ( not $taxon ) {
        Carp::confess('Cannot create taxon');
    }

    $sample = Genome::Sample->create(
        id => -1234,
        #name => 'HUMET-TEST-000',
        name => 'H_GV-933124G-S.MOCK',
        taxon_id => $taxon->id,
    );
    if ( not $sample ) {
        Carp::confess('Cannot create sample');
    }

    $library = Genome::Library->create(
        id => -12345,
        name => $sample->name.'-testlibs',
        sample_id => $sample->id,
    );
    if ( not $library ) { 
        Carp::confess('Cannot create library');
    }

    return 1;
}

sub taxon {
    my $class = shift;
    if ( not $taxon ) {
        $class->_taxon_sample_and_library;
    }
    return $taxon;
}

sub sample {
    my $class = shift;
    if ( not $sample ) {
        $class->_taxon_sample_and_library;
    }
    return $sample;
}

sub library {
    my $class = shift;
    if ( not $library ) {
        $class->_taxon_sample_and_library;
    }
    return $library;
}
#<>#

#< PP Models and Builds >#
sub processing_profile_for_454 {
    my $self = shift;

    my $pp = Genome::ProcessingProfile->get(2278045); # exists and cannot recreate w/ same params
    if ( not $pp ) {
        Carp::confess('Cannot create mc16s processing profile for 454');
    }

    return $pp;
}

sub processing_profile_for_sanger {
    my $self = shift;

    my $pp = Genome::ProcessingProfile->create(
        type_name => 'metagenomic composition 16s',
        name => 'MC16s Sanger TEST',
        sequencing_platform => 'sanger',
        amplicon_size => 1150,
        sequencing_center => 'gsc',
        assembler => 'phred_phrap',
        assembler_params => '-vector_bound 0 -trim_qual 0',
        classifier => 'rdp2-1',
        classifier_params => '-training_set broad',
    );

    if ( not $pp ) {
        Carp::confess('Cannot create mc16s processing profile for sanger');
    }

    return $pp;
}

sub processing_profile_for_solexa {
    my $self = shift;

    my $pp = Genome::ProcessingProfile->get( 2591278 );# exists and cannot recreate w/ same params
    if ( not $pp ) {
        Carp::confess('Can not get mc16s processing profile for solexa');
    }
    return $pp;
}

sub _model_for_sequencing_platform {
    my ($class, $sequencing_platform) = @_;

    Carp::confess('No sequencing platform given to get model') if not $sequencing_platform;

    my $sample = $class->sample or die; # confesses
    my $pp_method = 'processing_profile_for_'.$sequencing_platform;
    my $pp = $class->$pp_method or die; # confesses
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $model = Genome::Model->create(
        processing_profile => $pp,
        subject_name => $sample->name,
        subject_type => 'sample_name',
        data_directory => $tmpdir,
    );
    if ( not $model ) {
        Carp::confess('Cannot create mc16s model for '.$sequencing_platform);
    }

    my $instrument_data_method = '_instrument_data_'.$sequencing_platform;
    my $instrument_data = $class->$instrument_data_method;
    if ( not $instrument_data ) {
        Carp::confess('Cannot get solexa instrument data');
    }

    my $add_ok = $model->add_instrument_data($instrument_data);
    if ( not $add_ok ) {
        Carp::confess('Cannot add instrument data to model');
    }

    my @instrument_data = $model->instrument_data;
    if ( not @instrument_data ) {
        Carp::confess('Cannot get instrument data from model');
    }

    return $model;
}

sub model_for_454 {
    return $_[0]->_model_for_sequencing_platform('454');
}

sub model_for_sanger {
    return $_[0]->_model_for_sequencing_platform('sanger');
}

sub model_for_solexa {
    return $_[0]->_model_for_sequencing_platform('solexa');
}

sub example_build_for_model {
    my ($class, $model) = @_;

    Carp::confess('No mc16s model to create example build') if not $model;

    my $dir = $class->_example_directory_for_model($model) or die;
    my $build = $model->create_build(
        model=> $model,
        data_directory => $dir,
    );
    if ( not $build ) {
        Carp::confess('Cannot create mc16s build');
    }

    my $event = Genome::Model::Event->create(
        model => $model,
        build => $build,
        event_type => 'genome model build',
        event_status => 'Succeeded',
        date_completed => UR::Time->now,
    );
    if ( not $event ) {
        Carp::confess('Cannot create master event for example build');
    }
    my $master_event = $build->the_master_event;
    if ( not $master_event ) {
        Carp::confess('Cannot get the mster event for the example mc16s build');
    }

    return $build;
}
#<>#

#< Instrument Data >#
our $instrument_data_solexa;
sub _instrument_data_solexa {
    my $self = shift;

    return $instrument_data_solexa if $instrument_data_solexa;

    my $dir = $self->_instrument_data_dir_for_sequencing_platform(454) or die;
    my $library = $self->library or die; # confesses on error
    $instrument_data_solexa = Genome::InstrumentData::Solexa->create(
        id => -7777,
        flow_cell_id => 12345,
        lane => 1,
        run_type => 'paired',
        bam_path => '/gsc/var/cache/testsuite/data/Genome-Model/MetagenomicComposition16sSolexa/inst_data/input.bam',
    );
    if ( not $instrument_data_solexa ) {
        Carp::Confess( 'Could not creaste solexa instrument data' );
    }
    return $instrument_data_solexa;
}


our $instrument_data_454;
sub _instrument_data_454 {
    my $self = shift;

    return $instrument_data_454 if $instrument_data_454;

    my $dir = $self->_instrument_data_dir_for_sequencing_platform(454) or die; # confesses if not exist
    my $library = $self->library or die; # confesses on error
    $instrument_data_454 = Genome::InstrumentData::454->create(
        id => -7777,
        region_number => 2,
        total_reads => 20,
        run_name => 'R_2010_01_09_11_08_12_FLX08080418_Administrator_100737113',
        library => $library,
        sequencing_platform => '454',
    );
    if ( not $instrument_data_454 ) {
        Carp::confess('Cannot create 454 instrument data');
    }

    # Must overload this to return the fasta file. The real code goes through LIMS
    #  objects, which don't exist for this inst data.
    my $fasta_file = $dir.'/-7777.fasta';
    no warnings qw/ once redefine /;
    *Genome::InstrumentData::454::dump_fasta_file = sub{ return $fasta_file; };
    use warnings;

    my $fasta_file_from_inst_data = $instrument_data_454->dump_fasta_file;
    if ( $fasta_file_from_inst_data ne $fasta_file ) {
        Carp::confess('Could not set fasta file on 454 inst data');
    }

    return $instrument_data_454;
}

our $instrument_data_sanger;
sub _instrument_data_sanger {
    my $self = shift;

    return $instrument_data_sanger if $instrument_data_sanger;

    my $run_name = '01jan00.101amaa'; # 16may08.912pmba1
    my $library = $self->library or die; # confesses on error
    $instrument_data_sanger = Genome::InstrumentData::Sanger->create(
        id => $run_name,
        id => -8888,
        library => $library,
        sequencing_platform => 'sanger',
        subset_name => 1,
    );
    if ( not $instrument_data_sanger ) {
        Carp::confess('Cannot create sanger instrument data');
    }

    # Must overload this to not dump. The real code goes through LIMS
    #  objects, which don't exist for this inst data. Plus it's dumped already :)
    no warnings qw/ once redefine /;
    *Genome::InstrumentData::Sanger::dump_to_file_system = sub{ return 1; };
    use warnings;

    my $base_dir = $self->_base_directory('sanger');
    my $absolute_path = $base_dir.'/inst_data/'.$run_name;
    Carp::confess('No sanger instrument data directory: '.$absolute_path) if not -d $absolute_path;
    my $alloc = Genome::Disk::Allocation->__define__(
        owner_id => $instrument_data_sanger->id,
        owner_class_name => $instrument_data_sanger->class,
        disk_group_name => 'info_alignments',
        mount_path => $base_dir,
        group_subdirectory => 'inst_data',
        allocation_path => $run_name,
        absolute_path => $absolute_path,
    );
    if (not $alloc ) {
        Carp::confess('Could not create disk allocation for instrument data');
    }

    my $full_path_from_instrument_data = $instrument_data_sanger->full_path;
    if ( $full_path_from_instrument_data ne $alloc->absolute_path ) {
        Carp::confess('Could not set full path on sanger instrument data');
    }

    return $instrument_data_sanger;
}

#<>#

1;

