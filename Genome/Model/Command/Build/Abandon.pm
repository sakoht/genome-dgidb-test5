package Genome::Model::Command::Build::Abandon;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Build::Abandon {
    is => ['Genome::Model::Command'],
    has => [
            build_id => {
                         is => 'Number',
                         doc => 'The id of the build in which to update status',
                         is_optional => 1,
                     },
            build   => {
                        is => 'Genome::Model::Build',
                        id_by => 'build_id',
                        is_optional => 1,
                    },
        ],
};

sub help_detail {
    "This command will abandon the build and all events that make up the build";
}

sub execute {
    my $self = shift;
    my $model = $self->model;
    unless ($self->build_id) {
        $self->build_id($model->current_running_build_id);
    }
    my $build = $self->build;
    unless ($build) {
        $self->error_message('Build not found for model id '. $self->model_id .' and build id '. $self->build_id);
        return;
    }
    my $build_event = $build->build_event;
    unless ($build_event) {
        $self->error_message('No build event found for build '. $self->build_id);
        return;
    }
    unless ($build_event->abandon) {
        $self->error_message('Failed to abandon build '. $self->build_id);
        return;
    }
    return 1;
}


1;

