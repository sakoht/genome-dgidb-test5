package Genome::Model::Build::Command::Start;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
use Regexp::Common;

class Genome::Model::Build::Command::Start {
    is => 'Genome::Command::Base',
    doc => "Create and start a build.",
    has => [
        models => {
            is => 'Genome::Model',
            is_many => 1,
            doc => 'Model(s) to build. Resolved from command line via text string.',
            shell_args_position => 1,
        },
    ],
    has_optional => [
        job_dispatch => {
            doc => 'dispatch specification: an LSF queue or "inline"',
        },
        server_dispatch => {
            doc => 'dispatch specification: an LSF queue or "inline"',
        },
        data_directory => { },
        force => {
            is => 'Boolean',
            default_value => 0,
            doc => 'Force a new build even if existing builds are running.',
        },
        builds => {
            is => 'Genome::Model::Build',
            is_many => 1,
            is_output => 1,
        },
    ],

};

sub sub_command_sort_position { 1 }

sub help_synopsis {
    return <<EOS;
genome model build start 1234

genome model build start somename
# default values for dispatching will be either -s workflow -j apipe
# or come from the processing profile if available as a param

genome model build start somename -s workflow -j apipe
# run the server in the workflow queue, and jobs in the apipe queue

genome model build start somename -s inline -j inline
# run the server inline, and the jobs inline

EOS
}

sub help_detail {
    return <<EOS;
Make a new build for the specified model, and initiate execution of the build processes.

Builds with a defined workflow will run asynchronously.  Simple builds will run immediately
and this command will wait for them to finish.
EOS
}

sub execute {
    my $self = shift;

    my %create_params;
    $create_params{data_directory} = $self->data_directory if ($self->data_directory);
    my %start_params;
    $start_params{job_dispatch} = $self->job_dispatch if ($self->job_dispatch);
    $start_params{server_dispatch} = $self->server_dispatch if ($self->server_dispatch);

    my @models = $self->models;
    my @errors;
    for my $model (@models) {
        $self->status_message("Trying to start " . $model->__display_name__ . "...");
        my $transaction = UR::Context::Transaction->begin();
        my $build = eval {
            if (!$self->force && $model->running_builds) {
                die $self->error_message("Model (".$model->name.", ID: ".$model->id.") already has running builds. Use the '--force' param to override this and start a new build.");
            }

            $DB::single = 1;
            my $build = Genome::Model::Build->create(model_id => $model->id, %create_params);
            unless ($build) {
                die $self->error_message("Failed to create build for model (".$model->name.", ID: ".$model->id.").");
            }

            # Record newly created build so other tools can access them.
            # TODO: should possibly be part of the object class
            my @builds = $self->builds;
            push @builds, $build;
            $self->builds(\@builds);

            my $build_started = $build->start(%start_params);
            unless ($build_started) {
                die $self->error_message("Failed to start build (" . $build->__display_name__ . "): $@.");
            }
            return $build;
        };
        if ($build) {
            $self->status_message("Successfully started build (" . $build->__display_name__ . ").");
            $transaction->commit;
        }
        else {
            push @errors, $model->__display_name__ . ": " . $@;
            $transaction->rollback;
        }
    }

    $self->display_summary_report(scalar(@models), @errors);

    return !scalar(@errors);
}

1;

#$HeadURL$
#$Id$
