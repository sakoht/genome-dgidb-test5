package Genome::ProcessingProfile::Test;

use strict;
use warnings;

use base 'Genome::Utility::TestBase';

use Carp 'confess';
use Data::Dumper 'Dumper';
use Genome;
use Test::More;

#< MOCK ># 
sub create_mock_processing_profile {
    my ($self, $type_name) = @_; # seq plat for ref align

    # Create
    my %params = $self->valid_params_for_type_name($type_name);
    unless ( %params ) {
        confess "No params for type name ($type_name).";
    }
    my %create_params = map { $_ => delete $params{$_} } (qw/ class name type_name /);
    my $pp = $self->create_mock_object(%create_params)
        or confess "Can't create mock processing profile for '$type_name'";
    # Methods 
    $self->mock_methods(
        $pp,
        (qw/
            _initialize_model
            _initialize_build 
            _generate_events_for_build
            _generate_events_for_build_stage
            _generate_events_for_object
            _resolve_workflow_for_build
            _workflow_for_stage
            _merge_stage_workflows
            _resolve_log_resource
            _resolve_disk_group_name_for_build
            _build_success_callback
            params_for_class
            stages objects_for_stage classes_for_stage
            delete
            append_event_steps
            /),
    );

    # PP Params
    for my $param ( $pp->params_for_class ) {
        $self->mock_accessors($pp, $param);
        $pp->$param( delete $params{$param} );
    }

    # Stages
    for my $stage ( $pp->stages ) {
        $self->mock_methods(
            $pp,
            $stage.'_objects', $stage.'_job_classes',
        );
    }

    #< Specific Mocking >#
    my $additional_methods_method = '_add_mock_methods_to_'.join(
        '_', split(/\s/, $pp->type_name)
    );
    if ( $self->can($additional_methods_method) ) {
        $self->$additional_methods_method($pp)
            or confess "Can't add additional methods for $type_name";
    }

    return $pp;
}

#< Valid Params >#
my %TYPE_NAME_PARAMS = (
    tester => {
        class => 'Genome::ProcessingProfile::Tester',
        type_name => 'tester',
        name => 'Tester for Testing',
        sequencing_platform => 'solexa',
        dna_source => 'genomic',
        roi => 'mouse',
        append_event_steps => undef,
    }, 
    'amplicon assembly' => {
        class => 'Genome::ProcessingProfile::AmpliconAssembly',
        type_name => 'amplicon assembly',
        name => '16S Test 27F to 1492R (907R)',
        assembler => 'phredphrap',
        assembly_size => 1465,
        primer_amp_forward => '18SEUKF:ACCTGGTTGATCCTGCCAG',
        primer_amp_reverse => '18SEUKR:TGATCCTTCYGCAGGTTCAC',
        primer_seq_forward => '502F:GGAGGGCAAGTCTGGT',
        primer_seq_reverse => '1174R:CCCGTGTTGAGTCAAA',
        purpose => 'composition',
        region_of_interest => '16S',
        sequencing_center => 'gsc',
        sequencing_platform => 'sanger',
    }, 
    'metagenomic composition 16s sanger' => {
        class => 'Genome::ProcessingProfile::MetagenomicComposition16s',
        type_name => 'metagenomic composition 16s',
        name => '16S Test Sanger',
        amplicon_size => 1150,
        sequencing_center => 'gsc',
        sequencing_platform => 'sanger',
        assembler => 'phred_phrap',
        assembler_params => '-vector_bound 0 -trim_qual 0',
        classifier => 'rdp2-1',
        classifier_params => '-training_set broad',
    }, 
    'metagenomic composition 16s 454' => {
        class => 'Genome::ProcessingProfile::MetagenomicComposition16s',
        type_name => 'metagenomic composition 16s',
        name => '16S Test 454',
        amplicon_size => 200,
        sequencing_center => 'gsc',
        sequencing_platform => '454',
        classifier => 'rdp2-1',
        classifier_params => '-training_set broad',
    }, 
    'reference alignment solexa' => {
        class => 'Genome::ProcessingProfile::ReferenceAlignment::Solexa',
        type_name => 'reference alignment',
        name => 'Ref Align Solexa Test',
        sequencing_platform => 'solexa',
        dna_type => 'genomic dna',
        snv_detection_strategy => 'samtools',
        genotyper_params => undef,
        multi_read_fragment_strategy => undef,
        read_aligner_name => 'bwa',
        read_aligner_version => undef,
        read_aligner_params => undef,
        read_calibrator_name => undef,
        read_calibrator_params => undef,
        prior_ref_seq => undef,
        reference_sequence_name => undef,
        align_dist_threshold => undef,
    },
    'reference alignment 454' => {
        class => 'Genome::ProcessingProfile::ReferenceAlignment::454',
        type_name => 'reference alignment',
        name => 'Ref Align 454 Test',
        sequencing_platform => '454',
        dna_type => 'genomic dna',
        snv_detection_strategy => 'samtools',
        genotyper_params => undef,
        multi_read_fragment_strategy => undef,
        read_aligner_name => 'maq',
        read_aligner_version => undef,
        read_aligner_params => undef,
        read_calibrator_name => undef,
        read_calibrator_params => undef,
        prior_ref_seq => undef,
        reference_sequence_name => undef,
        align_dist_threshold => undef,
    },
    'de novo assembly' => {
        class => 'Genome::ProcessingProfile::DeNovoAssembly',
        name => 'Duh Novo Test',
        type_name => 'de novo assembly',
        sequencing_platform => 'solexa',
        assembler_name => 'velvet one-button',
        assembler_version => '0.7.30',
        assembler_params => '-hash_length 27 ',
        prepare_instrument_data_params => '-reads_cutoff 10000',
    },
    'virome screen' => {
	class => 'Genome::ProcessingProfile::ViromeScreen',
	name => 'Virome Screen Test',
	type_name => 'virome screen',
	sequencing_platform => '454',
    },
);
sub valid_params_for_type_name {
    my ($self, $type_name) = @_;

    confess "No type name given" unless $type_name;

    my ($match) = grep { m#$type_name# } sort { $b cmp $a } keys %TYPE_NAME_PARAMS;
    
    return unless exists $TYPE_NAME_PARAMS{$match};

    return %{$TYPE_NAME_PARAMS{$match}};
}

#< Additional Methods for Mock PP Type Names >#
# TODO
#sub _add_mock_methods_to_amplicon_assembly { }
sub _add_mock_methods_to_metagenomic_composition_16s {
    my ($self, $pp) = @_;

    $self->mock_methods(
        $pp, 
        (qw/ 
            _operation_params_as_hash
            assembler_params_as_hash classifier_params_as_hash 
            /),
    );

    return 1;
}

sub _add_mock_methods_to_de_novo_assembly { 
    my ($self, $pp) = @_;

    $self->mock_methods(
        $pp, 
        (qw/ 
            get_param_string_as_hash _validate_params_for_step 
            get_prepare_instrument_data_params get_assemble_params get_preprocess_params 
            /),
    );

    return 1;
}

#sub _add_mock_methods_to_tester { }
#sub _add_mock_methods_to_reference_alignement { }

# NO ADDITIONAL METHODS TO MOCK FOR VIROME SCREEN
#sub _add_mock_methods_to_virome_screen { }

#######################
# Type Name Test Base #
#######################

package Genome::ProcessingProfile::TestBase;

use strict;
use warnings;

use base 'Genome::Utility::TestBase';

use Data::Dumper 'Dumper';
require Scalar::Util;
use Test::More;

sub pp { # the valid processing profile
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
    my ($subclass) = $_[0]->test_class =~ m#Genome::ProcessingProfile::(\w+)#;
    return Genome::Utility::Text::camel_case_to_string($subclass);
}

sub full_type_name {
    my ($subclass) = $_[0]->test_class =~ m#Genome::ProcessingProfile::(.+)#;
    return join(
        ' ',
        map { Genome::Utility::Text::camel_case_to_string($_) }
        split('::', $subclass)
    );
}

sub params_for_test_class {
    my $self = shift;

    unless ( $self->{_params_for_class} ){
        my %params = Genome::ProcessingProfile::Test->valid_params_for_type_name( $self->full_type_name );
        delete $params{class};
        for my $key ( keys %params ) {
            delete $params{$key} unless defined $params{$key};
        }
        $self->{_params_for_class} = \%params;
    }

    return %{$self->{_params_for_class}};
}

# TODO test params?

#####################
# Amplicon Assembly #
#####################

package Genome::ProcessingProfile::AmpliconAssembly::Test;

use strict;
use warnings;

use base 'Genome::ProcessingProfile::TestBase';

sub invalid_params_for_test_class {
    return (
        primer_amp_forward => 'AAGGTGAGCCCGCGATGCGAGCTTAT',
        primer_amp_reverse => '55:55',
        sequencing_platform => 'super-seq',
        sequencing_center => 'monsanto',
        purpose => 'because',
    );
}

###############################
# Metagenomic Composition 16s #
###############################

############
# Commands #
############

package Genome::ProcessingProfile::Command::TestBase;

use strict;
use warnings;

use base 'Genome::Utility::TestBase';

sub test_class {
    return 'Genome::ProcessingProfile::Command::'.$$_[0]->subclass;
}

sub command_name {
    return Genome::Utility::Text::camel_case_to_string($_[0]->subclass);
}

sub params_for_test_class {
    return (
        $_[0]->_params_for_test_class,
    );
}

sub _params_for_test_class { 
    return;
}

sub test01_execute : Tests() {
    my $self = shift;

    ok($self->{_object}->execute, 'Executed '.$self->command_name);

    return 1;
}

sub test01_invalid : Tests() {
    my $self = shift;

    #ok($self->{_object}->execute, 'Executed '.$self->command_name);

    return 1;
}

1;

#$HeadURL$
#$Id$
