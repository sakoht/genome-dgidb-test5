package Genome::Model::RnaSeq::Command::DetectFusions::Base;

use strict;
use warnings;

use Genome;

class Genome::Model::RnaSeq::Command::DetectFusions::Base {
    is => "Command::V2",
    is_abstract => 1,
    has => [
        # params
        version => {
            is => 'Text',
            is_optional => 1,
            is_transient => 1,
            doc => 'the version of the fusion detector to run'
        },
        detector_params => {
            is => 'Text',
            is_optional => 1,
            is_transient => 1,
            doc => 'parameters for the chosen fusion detector'
        },
        build_id => {
            is => 'Integer',
            is_optional => 0,
            is_input => 1,
            implied_by => 'build',
            doc => 'build id used in this workflow'
        },
        build => {
            is => "Genome::Model::Build",
            id_by  => 'build_id',
            doc => 'build object',
        },
        lsf_resource => {
            default_value => "-R 'select[type==LINUX64 && mem>16000] span[hosts=1] rusage[mem=16000]' -M 16000000 -n 8",
            is_param => 1,
            is_optional => 1,
            doc => 'default LSF resource expectations',
        },

    ],
    doc => 'run a generic fusion detector',
};

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    return unless $self;

    my ($detector, $version, $params) = split(/\s+/, $self->build->model->fusion_detection_strategy);
    ($params) = $params =~ /^\[(.+)\]$/ if $params;
    $self->detector_params($params);
    $self->version($version);

    return $self;
}

sub _link_build_to_result {
    my $self = shift;
    my $result = shift;

    my $link = $result->add_user(user => $self->build, label => 'uses');
    if ($link) {
        $self->status_message("Linked result " . $result->id . " to the build");
    }
    else {
        $self->error_message(
            "Failed to link the build to the result "
            . $result->__display_name__
            . "!"
        );
        die $self->error_message;
    }
    return 1;
}

1;
