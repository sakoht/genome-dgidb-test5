package Genome::Model::Command::Define::ReferenceAlignment;

use strict;
use warnings;

use Genome;

require Carp;
use Regexp::Common;

class Genome::Model::Command::Define::ReferenceAlignment {
    is => [
        'Genome::Model::Command::Define',
        'Genome::Command::Base',
        ],
    has => [
        reference_sequence_build => {
            is => 'Genome::Model::Build::ImportedReferenceSequence',
            doc => 'ID or name of the reference sequence to align against',
            default_value => 'NCBI-human-build36',
            is_input => 1,
        },
        annotation_reference_build => {
            is => 'Genome::Model::Build::ImportedAnnotation',
            doc => 'ID or name of the the build containing the reference transcript set used for variant annotation',
            is_optional => 1,
            is_input => 1,
        },
        dbsnp_build => {
            is => 'Genome::Model::Build::ImportedVariationList',
            doc => 'ID or name of the dbSNP build to compare against',
            is_optional => 1,
            is_input => 1,
        },
        target_region_set_names => {
            is => 'Text',
            is_optional => 1,
            is_many => 1,
            doc => 'limit the model to take specific capture or PCR instrument data',
        },
        region_of_interest_set_name => {
            is => 'Text',
            is_optional => 1,
            doc => 'limit coverage and variant detection to within these regions of interest',
        }
    ]
};

sub _shell_args_property_meta {
    my $self = shift;
    return $self->Genome::Command::Base::_shell_args_property_meta(@_);
}

sub type_specific_parameters_for_create {
    my $self = shift;
    my $rsb = $self->_resolve_param('reference_sequence_build');
    my $arb = $self->_resolve_param('annotation_reference_build');
    my $dbsnp = $self->_resolve_param('dbsnp_build');
    my @params;
    push(@params, reference_sequence_build => $rsb) if $rsb;
    push(@params, annotation_reference_build => $arb) if $arb;
    push(@params, dbsnp_build => $dbsnp) if $dbsnp;
    return @params;
}

sub listed_params {
    return qw/ id name data_directory subject_name subject_type processing_profile_id processing_profile_name reference_sequence_name annotation_reference_name /;
}

sub execute {
    my $self = shift;
    
    my $result = $self->SUPER::_execute_body(@_);
    return unless $result;

    my $model = Genome::Model->get($self->result_model_id);
    unless ($model) {
        $self->error_message("No model generated for " . $self->result_model_id);
        return;
    }

    # LIMS is preparing actual tables for these in the dw, until then we just manage the names.
    my @target_region_set_names = $self->target_region_set_names;
    if (@target_region_set_names) {
        for my $name (@target_region_set_names) {
            my $i = $model->add_input(value_class_name => 'UR::Value', value_id => $name, name => 'target_region_set_name');
            if ($i) {
                $self->status_message("Modeling instrument-data from target region '$name'");
            }
            else {
                $self->error_message("Failed to add target '$name'!");
                $model->delete;
                return;
            }
        }
    }
    else {
        $self->status_message("Modeling whole-genome (non-targeted) sequence.");
    }
    if ($self->region_of_interest_set_name) {
        my $name = $self->region_of_interest_set_name;
        my $i = $model->add_input(value_class_name => 'UR::Value', value_id => $name, name => 'region_of_interest_set_name');
        if ($i) {
            $self->status_message("Analysis limited to region of interest set '$name'");
        }
        else {
            $self->error_message("Failed to add region of interest set '$name'!");
            $model->delete;
            return;
        }
    } else {
        $self->status_message("Analyzing whole-genome (non-targeted) reference.");
    }

    return $result;
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

1;

