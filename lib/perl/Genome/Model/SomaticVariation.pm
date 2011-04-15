package Genome::Model::SomaticVariation;
#:adukes short term, keep_n_most_recent_builds shouldn't have to be overridden like this here.  If this kind of default behavior is acceptable, it belongs in the base class

use strict;
use warnings;

use Genome;

class Genome::Model::SomaticVariation {
    is  => 'Genome::Model',
    has => [
        snv_detection_strategy => {
            is => 'Text',
            via => 'processing_profile',
        },
        sv_detection_strategy => {
            is => 'Text',
            via => 'processing_profile',
        },
        indel_detection_strategy => {
            is => 'Text',
            via => 'processing_profile',
        },
        cnv_detection_strategy => {
            is => 'Text',
            via => 'processing_profile',
        },
        tumor_model_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'tumor_model', value_class_name => 'Genome::Model::ReferenceAlignment' ],
            is_many => 0,
            is_mutable => 1,
            is_optional => 0,
            doc => 'tumor model for somatic analysis'
        },
        tumor_model => {
            is => 'Genome::Model::ReferenceAlignment',
            id_by => 'tumor_model_id',
        },
        tumor_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'tumor_build', value_class_name => 'Genome::Model::Build::ReferenceAlignment'],
            is_many => 0,
            is_mutable => 1,
            is_optional => 1,
            doc => 'last complete tumor build, updated when a new SomaticVariation build is created',
        },
        tumor_build => {
            is => 'Genome::Model::Build::ReferenceAlignment',
            id_by => 'tumor_build_id',
        },
        normal_model_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'normal_model', value_class_name => 'Genome::Model::ReferenceAlignment' ],
            is_many => 0,
            is_mutable => 1,
            is_optional => 0,
            doc => 'normal model for somatic analysis'
        },
        normal_model => {
            is => 'Genome::Model::ReferenceAlignment',
            id_by => 'normal_model_id',
        },
        normal_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'normal_build', value_class_name => 'Genome::Model::Build::ReferenceAlignment'],
            is_many => 0,
            is_mutable => 1,
            is_optional => 1,
            doc => 'last complete normal build, updated when a new SomaticVariation build is created',
        },
        normal_build => {
            is => 'Genome::Model::Build::ReferenceAlignment',
            id_by => 'normal_build_id',
        },
        annotation_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'annotation_build', value_class_name => 'Genome::Model::Build::ImportedAnnotation' ],
            is_many => 0,
            is_mutable => 1,
            is_optional => 0,
            doc => 'annotation build for fast tiering'
        },
        annotation_build => {
            is => 'Genome::Model::Build::ImportedAnnotation',
            id_by => 'annotation_build_id',
        },
        previously_discovered_variations_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'previously_discovered_variations', value_class_name => "Genome::Model::Build::ImportedVariationList"],
            is_many => 0,
            is_mutable => 1,
            is_optional => 0,
            doc => 'previous variants genome feature set to screen somatic mutations against',
        },
        previously_discovered_variations_build => {
            is => 'Genome::Model::Build::ImportedVariationList',
            id_by => 'previously_discovered_variations_build_id',
        },
    ],
};

sub create {
    my $class = shift;
    my %params = @_;

    $DB::single = 1;

    my $tumor_model = $params{tumor_model};
    my $normal_model =  $params{normal_model};
    my $annotation_build = $params{annotation_build};
    my $previously_discovered_variations_build = $params{previously_discovered_variations_build};

    unless($tumor_model) {
        $class->error_message('No tumor model provided.' );
        return;
    }

    unless($normal_model) {
        $class->error_message('No normal model provided.');
        return;
    }

    unless($annotation_build) {
        $class->error_message('No annotation build provided.' );
        return;
    }

    unless($previously_discovered_variations_build) {
        $class->error_message('No previous variants build provided.');
        return;
    }

    my $tumor_subject = $tumor_model->subject;
    my $normal_subject = $normal_model->subject;

    if($tumor_subject->can('source') and $normal_subject->can('source')) {

        my $tumor_source = $tumor_subject->source;
        my $normal_source = $normal_subject->source;

        unless ($tumor_source eq $normal_source) {
            my $tumor_common_name = $tumor_source->common_name || "unknown";
            my $normal_common_name = $normal_source->common_name || "unknown";
            die $class->error_message("Tumor model and normal model samples do not come from the same individual.  Tumor common name is $tumor_common_name. Normal common name is $normal_common_name.");
        }
        $params{subject_id} = $tumor_subject->id;
        $params{subject_class_name} = $tumor_subject->class;
        $params{subject_name} = $tumor_subject->common_name || $tumor_subject->name;

    } else {
        $class->error_message('Unexpected subject for tumor or normal model!');
        return;
    }

    my $self = $class->SUPER::create(%params);

    unless ($self){
        $class->error_message('Error in model creation');
        return;
    }

    unless($self->tumor_model) {
        $self->error_message('No tumor model on model!' );
        return;
    }

    unless($self->normal_model) {
        $self->error_message('No normal model on model!');
        return;
    }

    unless($self->annotation_build) {
        $self->error_message('No annotation build on model!' );
        return;
    }

    unless($self->previously_discovered_variations_build) {
        $self->error_message('No previous variants build on model!');
        return;
    }

    return $self;
}

sub update_tumor_and_normal_build_inputs {
    my $self = shift;
    
    my $tumor_model = $self->tumor_model;
    my $tumor_build = $tumor_model->last_complete_build;
    $self->tumor_build_id($tumor_build->id) if $tumor_build and $self->tumor_build_id ne $tumor_build->id; 

    my $normal_model = $self->normal_model;
    my $normal_build = $normal_model->last_complete_build;
    $self->normal_build_id($normal_build->id) if $normal_build and $self->normal_build_id ne $normal_build->id; 

    return 1;
}

sub inputs_necessary_for_copy {
    my $self = shift;
    my @inputs_to_copy = $self->SUPER::inputs_necessary_for_copy;
    # The 2nd grep is to skip all model inputs that have already been set. This avoids a crash problem when genome model copy will have already copied the input over via its accessor
    @inputs_to_copy = grep {my $input = $_->name; !(grep{$input eq $_->name} $self->inputs)} @inputs_to_copy;
    return @inputs_to_copy; 
}
1;
