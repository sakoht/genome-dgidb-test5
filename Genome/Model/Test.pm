package Genome::Model::Test;

use strict;
use warnings;

use base 'Genome::Utility::TestBase';

use Carp 'confess';
use Data::Dumper 'Dumper';
require File::Temp;
require Genome;
require Genome::ProcessingProfile::Test;
require Genome::Utility::Text;
use Test::More;

#< Tester Type Name >#
class Genome::Model::Tester { # 'real' model for testing
    is => 'Genome::Model',
};
class Genome::Model::Build::Tester { # 'real' model for testing
    is => 'Genome::Model::Build',
};

sub test_class {
    return 'Genome::Model';
}

sub params_for_test_class {
    return (
        name => 'Test Sweetness',
        subject_name => $_[0]->mock_sample_name,
        subject_type => 'sample_name',
        data_directory => $_[0]->tmp_dir,
        processing_profile_id => $_[0]->_tester_processing_profile->id,
    );
}

sub required_params_for_class {
    return (qw/ subject_type subject_name processing_profile_id /);
}

sub optional_params_for_class {
    return (qw/ name data_directory /);
}

sub invalid_params_for_test_class {
    return (
        subject_name => 'invalid_subject_name',
        subject_type => 'invalid_subject_type',
        processing_profile_id => '-999999',#'duidudrted',
    );
}

sub _model { # real model we are creating
    return $_[0]->{_object};
}

sub mock_sample_name {
    return 'H_GV-933124G-S.MOCK',
}

sub _instrument_data {
    return $_[0]->{_instrument_data}
}

sub _tester_processing_profile {
    my $self = shift;

    unless ( $self->{_processing_profile} ) {
    $self->{_processing_profile} = Genome::ProcessingProfile::Test->create_mock_processing_profile('tester')
        or confess;
}
    return $self->{_processing_profile};
}
            
sub test_startup : Test(startup => 3) {
    my $self = shift;

    # UR
    $ENV{UR_DBI_NO_COMMIT} = 1;
    ok($ENV{UR_DBI_NO_COMMIT}, 'No commit') or confess;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    ok($ENV{UR_USE_DUMMY_AUTOGENERATED_IDS}, 'Dummy ids') or confess;
    ok($self->create_mock_sample, 'Create mock sample');

    return 1;
}

sub test_shutdown : Test(shutdown => 1) {
    my $self = shift;

    ok($self->_model->delete, 'Delete model');

    return 1;
}

sub test01_directories_and_links : Tests(4) {
    my $self = shift;

    my $model = $self->_model;
    is($model->data_directory, $self->tmp_dir, "Model data directory");
    ok($model->resolve_data_directory, "Resolve data directory");
    ok(-d $model->alignment_links_directory, "Alignment links directory");
    ok(-d $model->base_model_comparison_directory, "Model comparison directory");

    return 1;
}

sub test02_instrument_data : Tests() { 
    my $self = shift;

    my $model = $self->_model;
    my @instrument_data = $self->create_mock_solexa_instrument_data(2); # dies if no workee

    # overwrite G:ID get to not do a full lookup and save time (~ 10 sec)
    no warnings qw/ once redefine /;
    local *Genome::InstrumentData::get = sub{ return @instrument_data; };
    
    # compatible
    my @compatible_id = $model->compatible_instrument_data;
    is_deeply(
        \@compatible_id,
        \@instrument_data,
        "compatible_instrument_data"
    );

    # available/unassigned
    can_ok($model, 'unassigned_instrument_data'); # same as available
    my @available_id = $model->available_instrument_data;
    is_deeply(
        \@available_id,
        \@compatible_id,
        "available_instrument_data"
    );

    ## Can't get instrument_data_assignments to work...so overwrite 
    my @idas = $self->create_mock_instrument_data_assignments($model, @instrument_data);
    local *Genome::Model::instrument_data_assignments = sub{ return @idas; };
    $idas[0]->first_build_id(1);
    my @model_id = $model->instrument_data;
    is_deeply(\@model_id, \@instrument_data, 'instrument_data');
    my @built_id = $model->built_instrument_data; # should by id[0]
    is_deeply(\@built_id, [ $instrument_data[0] ], 'built_instrument_data');
    my @unbuilt_id = $model->unbuilt_instrument_data; # should by id[1]
    is_deeply(\@unbuilt_id, [ $instrument_data[1] ], "unbuilt_instrument_data");

    return 1;
}

#< MOCK ># 
sub mock_model_dir_for_type_name {
    confess "No type name given" unless $_[1];
    return $_[0]->dir.'/'.Genome::Utility::Text::string_to_camel_case($_[1]);
}

sub create_basic_mock_model {
    my ($self, %params) = @_;

    my $type_name = delete $params{type_name};
    unless ( $type_name ) {
        confess "No type name given to create mock model";
    }
    
    # Processing profile
    my $pp = Genome::ProcessingProfile::Test->create_mock_processing_profile($type_name)
        or confess "Can't create mock $type_name processing profile";

    my $model_data_dir = ( delete $params{use_mock_dir} ) 
    ? $self->mock_model_dir_for_type_name($type_name)
    : File::Temp::tempdir(CLEANUP => 1);

    confess "Can't find mock model data directory: $model_data_dir" unless -d $model_data_dir;
    
    # Model
    my $sample = $self->create_mock_sample;
    my $model = $self->create_mock_object(
        class => 'Genome::Model::'.Genome::Utility::Text::string_to_camel_case($pp->type_name),
        name => 'mr. mock',
        subject_name => $sample->name,
        subject_type => 'sample_name',
        processing_profile_id => $pp->id,
        data_directory => $model_data_dir,
    )
        or confess "Can't create mock $type_name model";

    # Methods in base Genome::Model
    $self->mock_methods(
        $model,
        (qw/
            running_builds current_running_build current_running_build_id
            completed_builds last_complete_build last_complete_build_id
            succeeded_builds last_succeeded_build last_succeeded_build_id
            compatible_instrument_data assigned_instrument_data unassigned_instrument_data
            /),
    ) or confess "Can't add mock methods to $type_name model";

    # Methods in subclass
    my $add_mock_methods_to_model = '_add_mock_methods_to_'.join('_', split(' ',$model->type_name)).'_model';
    if ( $self->can($add_mock_methods_to_model) ) {
        $self->$add_mock_methods_to_model($model)
            or confess;
    }

    return $model;
}

sub create_mock_model {
    my ($self, %params) = @_;

    my $model = $self->create_basic_mock_model(%params);
    confess "Can't create mock ".$model->type_name." model" unless $model;

    my $build = $self->add_mock_build_to_model($model)
        or confess "Can't add mock build to mock ".$model->type_name." model";

    if ( $model->sequencing_platform ) {
        my @idas = $self->create_and_assign_mock_instrument_data_to_model($model, $params{instrument_data_count})
            or confess "Can't add mock instrument data to mock ".$model->type_name." model";
    }
    
    return $model;
}
 
sub create_mock_sample {
    my $self = shift;

    my $taxon = $self->create_mock_object(
        class => 'Genome::Taxon',
        domain => 'Eukaryota',
        species_name => 'human',
        species_name => 'Homo sapiens',
        current_default_prefix => 'H_',
        legacy_org_id => 17,
        estimated_orgainsm_genome_size => 3200000000,
        current_genome_refseq_id => 2817463805,
        ncbi_taxon_id => 9606,
    ) or confess "Can't create mock taxon";

    my $source = $self->create_mock_object(
        class => 'Genome::SampleSource',
        taxon_id => $taxon->id,
        name => $self->mock_sample_name,
    ) or confess "Can't create mock source";

    my $sample = $self->create_mock_object(
        class => 'Genome::Sample',
        source_id => $source->id,
        source_type => 'organism individual',
        taxon_id => $taxon->id,
        name => $self->mock_sample_name,
        common_name => 'normal',
        extraction_label => 'S.MOCK',
        extraction_type => 'genomic dna',
        extraction_desc => undef,
        cell_type => 'primary',
        gender => 'female',
        tissue_desc => 'skin, nos',
        tissue_label => '31412',
        organ_name => undef,
    ) or confess "Can't create mock sample";

    return $sample;
}

sub add_mock_build_to_model {
    my ($self, $model) = @_;

    confess "No model given to add mock build" unless $model;

    #< Build
    my $build = $self->create_mock_object(
        class => 'Genome::Model::Build::'.Genome::Utility::Text::string_to_camel_case($model->type_name),
        model => $model,
        model_id => $model->id,
        data_directory => $model->data_directory.'/build', #FIXME
        type_name => $model->type_name,
    ) or confess "Can't create mock ".$model->type_name." build";

    # data directory:
    # tmp - use build id
    # mock dir - no id
    $build->data_directory( $model->data_directory.'/build'.( $model->data_directory =~ m#^/tmp# ? $build->id : ''));
    mkdir $build->data_directory unless -d $build->data_directory;

    $self->mock_methods(
        $build,
        (qw/
            reports_directory resolve_reports_directory
            build_event build_events build_status
            date_completed date_scheduled
            add_report get_report reports 
            /),
    ) or confess "Can't add methods to mock build";

    #< Event
    $self->add_mock_event_to_build($build)
        or confess "Can't add mock event to mock build";

    #< Methods in subclass
    my $add_mock_methods_to_build = '_add_mock_methods_to_'.join('_', split(' ',$model->type_name)).'_build';
    if ( $self->can($add_mock_methods_to_build) ) {
        $self->$add_mock_methods_to_build($build)
            or confess;
    }

    return $build;
}

sub add_mock_event_to_build {
    my ($self, $build) = @_;

    confess "No build given to add mock event" unless $build;

    my $event = $self->create_mock_object(
        class => 'Genome::Model::Command::Build',
        model_id => $build->model_id,
        build_id => $build->id,
        event_type => 'genome model build',
        event_status => 'Succeeded',
        user_name => $ENV{USER},
        date_scheduled => UR::Time->now,
        date_completed => UR::Time->now,
    ) or confess "Can't create mock build event for ".$build->type_name." build";

    $self->mock_methods(
        $event,
        (qw/ desc /),
    ) or confess "Can't add methods to mock build";

    return $event;
}

sub create_and_assign_mock_instrument_data_to_model {
    my ($self, $model, $cnt) = @_;

    confess "No model to create and assign instrument data" unless $model and $model->isa('Genome::Model');

    unless ( $model->sequencing_platform ) {
        confess "No sequencing platform to add mock instrument data to model";
    }

    # Instrument Data
    my $create_mock_instrument_data_method = sprintf(
        'create_mock_%s_instrument_data',
        $model->sequencing_platform,
    );
    unless ( $self->can($create_mock_instrument_data_method) ) {
        confess "No method to create ".$model->sequencing_platform." instrument data";
    }
    my @instrument_data = $self->$create_mock_instrument_data_method($cnt)
        or confess "Can't create mock ".$model->sequencing_platform." instrument data";

    # Instrument Data Assignments
    my @instrument_data_assignments = $self->create_mock_instrument_data_assignments($model, @instrument_data)
        or confess "Can't create mock instrument data assignments";

    return @instrument_data_assignments;
}

sub create_mock_instrument_data_assignments {
    my ($self, $model, @instrument_data) = @_;

    confess "No model to assign instrument data" unless $model and $model->isa('Genome::Model');
    confess "No instrument data to assign to model" unless @instrument_data;
    
    my @instrument_data_assignments;
    for my $instrument_data ( @instrument_data ) {
        my $instrument_data_assignment = $self->create_mock_object(
            class => 'Genome::Model::InstrumentDataAssignment',
            model => $model,
            model_id => $model->id,
            instrument_data => $instrument_data,
            instrument_data_id => $instrument_data->id,
            first_build_id => undef,
        ) or confess;
        push @instrument_data_assignments, $instrument_data_assignment;
    }

    return @instrument_data_assignments;
}

sub create_mock_sanger_instrument_data {
    my ($self , $cnt) = @_;

    $cnt ||= 1;
    my $dir = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Sanger';

    my @id;
    for my $i (1..$cnt) {
        my $run_name = '0'.$i.'jan00.101amaa';
        my $full_path = $dir.'/'.$run_name;
        confess "Mock instrument data directory ($full_path) does not exist" unless -d $full_path;
        my $id = $self->create_mock_object(
            class => 'Genome::InstrumentData::Sanger',
            id => $run_name,
            run_name => $run_name,
            sequencing_platform => 'sanger',
            seq_id => $run_name,
            sample_name => 'unknown',
            subset_name => 1,
            library_name => 'unknown',
            full_path => $full_path,
        )
            or die "Can't create mock sanger instrument data";
        $id->mock('resolve_full_path', sub{ return $full_path; });
        $id->mock('dump_to_file_system', sub{ return 1; });
        push @id, $id;
    }

    return @id;
}

sub create_mock_solexa_instrument_data {
    my ($self , $cnt) = @_;

    $cnt ||= 1;
    my $dir = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Solexa';

    my @id;
    my $seq_id = 2338814064;
    for my $i (1..$cnt) {
        my $full_path = $dir.'/'.++$seq_id;
        my $id = $self->create_mock_object(
            class => 'Genome::InstrumentData::Solexa',
            id => $seq_id,
            run_name => '071015_HWI-EAS109_0000_13651',
            sequencing_platform => 'solexa',
            seq_id => $seq_id,
            sample_name => $self->mock_sample_name,
            subset_name => $i,
            library_name => 'H_GV-933124G-S.MOCK-lib1',
            full_path => $full_path,
            read_length => 32,
            is_paired_end => 0,
            lane => $i,
            flow_cell_id => 13651,
        ) or confess "Can't create mock solexa id #$cnt";
        $id->mock('fastq_filenames', sub{ return glob($_[0]->full_path.'/*.fastq'); });
        $id->mock('resolve_full_path', sub{ return $full_path; });
        $id->mock('dump_to_file_system', sub{ return 1; });
        push @id, $id;
    }

    return @id;
}

#< Additional Methods for Mock Models Type Names >#
# amplicon assembly
sub _add_mock_methods_to_amplicon_assembly_build { 
    my ($self, $build) = @_;

    $self->mock_methods(
        $build,
        Genome::AmpliconAssembly->helpful_methods,
        (qw/
            amplicon_assembly
            link_instrument_data 
            /),
    );

    return 1;

}

# de novo assembly
sub _add_mock_methods_to_de_novo_assembly_build { 
    my ($self, $build) = @_;

    $self->mock_methods(
        $build,
        (qw/ velvet_fastq_file /),
    );

    return 1;
}

# reference alignment
sub _additional_methods_to_reference_alignment_model {
    my ($self, $model) = @_;

    Genome::Utility::TestBase->mock_methods(
        $model,
        (qw/ 
            complete_build_directory 
            _filtered_variants_dir 
            gold_snp_file 
            /)
    );

    return 1;
}

sub _additional_methods_to_reference_alignment_build {
    my ($self, $build) = @_;

    if ( $build->model->sequencing_platform eq 'solexa' ) {
        $self->mock_methods(
            $build,
            (qw/ snp_related_metric_directory /),
        );
        $build->mock('_variant_list_files', sub{ return glob($build->snp_related_metric_directory.'/snps_*'); });
    }
    # else { # 454 

    return 1;

}
# TODO?sub _additional_methods_to_reference_alignment_model { 454 and solexa

#< COPY DATA >#
sub copy_test_dir {
    my ($self, $source_dir, $dest) = @_;

    Genome::Utility::FileSystem->validate_existing_directory($dest)
        or confess;

    my $dh = Genome::Utility::FileSystem->open_directory($source_dir)
        or confess;

    while ( my $file = $dh->read ) {
        next if $file =~ m#^\.#;
        # TODO recurse for directories?
        confess "Can't recursively copy directories" if -d $file;
        my $from = "$source_dir/$file";
        File::Copy::copy($from, $dest)
                or die "Can't copy ($from) to ($dest): $!\n";
        }

        return 1;
}

#######################
# Type Name Test Base #
#######################
# Since models don't have any additional params when creating, we'll test the real methods
#  with a mock model (tester).

# TODO


package Genome::Model::TestBase;

use strict;
use warnings;

#use base 'Genome::Utility::TestBase';
use base 'Test::Class';

use Data::Dumper 'Dumper';
require Scalar::Util;
use Test::More;

sub _model { # the valid model
    return $_[0]->{_object};
}

sub class_name {
    return ( Scalar::Util::blessed($_[0]) || $_[0] );
}

sub test_class {
    my $class = $_[0]->class_name;
    $class =~ s#::Test$##;
    return $class
}

sub type_name {
    my ($subclass) = $_[0]->test_class =~ m#Genome::Model::(\w+)#;
    return Genome::Utility::Text::camel_case_to_string($subclass);
}

sub params_for_test_class {
    return Genome::Model::Test->valid_params_for_type_name( $_[0]->type_name );
}

sub test_shutdown : Test(shutdown => 0) {
    my $self = shift;
    
    diag($self->_model->model_link);
    
    return 1;
}


#####################
# Amplicon Assembly #
#####################

package Genome::Model::Test::AmpliconAssembly;

use strict;
use warnings;

use base 'Genome::Model::TestBase';

#######################
# Reference Alignment #
#######################

package Genome::Model::Test::ReferenceAlignment::454;

use strict;
use warnings;

use base 'Genome::Model::TestBase';

package Genome::Model::Test::ReferenceAlignment::Solexa;

use strict;
use warnings;

use base 'Genome::Model::TestBase';

###################################################
###################################################

1;

#$HeadURL$
#$Id$
