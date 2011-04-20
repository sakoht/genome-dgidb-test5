# FIXME ebelter
#  Long: remove this and all define modeuls to have just one that can handle model inputs
package Genome::Model::Command::Define::SomaticVariation;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Define::SomaticVariation {
    is => [
    'Genome::Model::Command::Define',
    'Genome::Command::Base',
    ],
    has => [
        tumor_model => {
            is => 'Genome::Model::ReferenceAlignment',
            is_input => 1,
            doc => 'Name or id of tumor model being analyzed',
        },
        normal_model => {
            is => 'Genome::Model::ReferenceAlignment',
            is_input => 1,
            doc => 'Name or id of normal model being analyzed',
        },
        previously_discovered_variations_build => {
            is => 'Genome::Model::Build::ImportedVariationList',
            is_input => 1, 
            doc => 'Id of imported variants build to screen somatic variants against',
        },
        annotation_build => {
            is => 'Genome::Model::Build::ImportedAnnotation',
            is_input => 1, 
            doc => 'Id of annotation build to use for fast tiering of variants',
        },
        subject_name => {
            is => 'Text',
            is_input => 1,
            is_optional => 1,
            doc => 'Subject name is derived from normal and tumor models and is not necessary as input to somatic models',
        },
    ],
};

sub help_synopsis {
    return <<"EOS"
genome model define somatic-variation --tumor-model aml3-tumor1-v2 --normal-model aml3-normal1-v2  --annotation-build 102550711 --previously-discovered-variations-build 106227442 --processing-profile-id 2573882 --model-name adukes_test_somatic_model 
EOS
}

sub help_detail {
    return <<"EOS"
This defines a new genome model representing the somatic analysis between a normal and tumor model.
EOS
}

sub _shell_args_property_meta {
    my $self = shift;
    return $self->Genome::Command::Base::_shell_args_property_meta(@_);
}

sub _resolve_param {
    my ($self, $param) = @_;

    my $param_meta = $self->__meta__->property($param);
    Carp::confess("Request to resolve unknown property '$param'.") if (!$param_meta);
    my $param_class = $param_meta->data_type;

    my $value = $self->$param;
    return unless $value; # not specified
    return $value if ref($value); # already an object

    my @objs = $self->resolve_param_value_from_text($value, $param_class);
    if (@objs != 1) {
        Carp::confess("Unable to find unique $param_class identified by '$value'. Results were:\n" .
            join('\n', map { $_->__display_name__ . '"' } @objs ));
    }
    $self->$param($objs[0]);
    return $self->$param;
}

sub type_specific_parameters_for_create {
    my $self = shift;

    my @params = ();

    push @params,(
        tumor_model => $self->tumor_model,
        normal_model => $self->normal_model,
        annotation_build => $self->annotation_build,
        previously_discovered_variations_build => $self->previously_discovered_variations_build
    );


    return @params;
}

sub execute {
    my $self = shift;
    $DB::single = 1;

    $self->normal_model($self->_resolve_param('normal_model'));
    unless(defined $self->normal_model) {
        $self->error_message("Could not get a model for normal model id: " . $self->normal_model_id);
        return;
    }
    $self->tumor_model($self->_resolve_param('tumor_model'));
    unless(defined $self->tumor_model) {
        $self->error_message("Could not get a model for tumor model id: " . $self->tumor_model_id);
        return;
    }
    $self->annotation_build($self->_resolve_param('annotation_build'));
    unless(defined $self->annotation_build) {
        $self->error_message("Could not get a build for annotation build id: " . $self->annotation_build_id);
        return;
    }
    $self->previously_discovered_variations_build($self->_resolve_param('previously_discovered_variations_build'));
    unless(defined $self->previously_discovered_variations_build) {
        $self->error_message("Could not get a build for previous variants build id: " . $self->previously_discovered_variations_build_id);
        return;
    }

    my $tumor_subject = $self->tumor_model->subject;
    my $normal_subject = $self->normal_model->subject;

    if($tumor_subject->can('source') and $normal_subject->can('source')) {

        my $tumor_source = $tumor_subject->source;
        my $normal_source = $normal_subject->source;
        unless($tumor_source) {
            die $self->error_message("Could not get a source for the tumor subject: " . Data::Dumper::Dumper $tumor_subject);
        }
        unless($normal_source) {
            die $self->error_message("Could not get a source for the normal subject: " . Data::Dumper::Dumper $normal_subject);
        }
        
        unless ($tumor_source eq $normal_source) {
            my $tumor_common_name = $tumor_source->common_name || "unknown";
            my $normal_common_name = $normal_source->common_name || "unknown";
            die $self->error_message("Tumor model and normal model samples do not come from the same individual.  Tumor common name is $tumor_common_name. Normal common name is $normal_common_name.");
        }
        $self->subject_id($tumor_subject->id);
        $self->subject_class_name($tumor_subject->class);
        $self->subject_name($tumor_subject->name);
    
    } else {
        $self->error_message('Unexpected subject for tumor or normal model!');
        return;
    }

    # run Genome::Model::Command::Define execute
    my $super = $self->super_can('_execute_body');
    return $super->($self,@_);
}

1;
