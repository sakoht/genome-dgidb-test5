package Genome::Model::Build::Command::Start;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
use Regexp::Common;

class Genome::Model::Build::Command::Start {
    is => 'Command',
    doc => "Create and start a build.",
    has => [
        model_identifier => {
            is => 'Text',
            doc => 'Model identifier.  Use model id or name.',
            shell_args_position => 1,
        },
    ],
    has_optional => [
        job_dispatch => {
#            default_value => 'apipe',
#            is_constant => 1,
            doc => 'dispatch specification: an LSF queue or "inline"'
        },
        server_dispatch => {
#            default_value => 'long',
#            is_constant => 1,
            doc => 'dispatch specification: an LSF queue or "inline"',
        },
        data_directory => { },
        force => {
            is => 'Boolean',
            default_value => 0,
            doc => 'Force a new build even if existing builds are running.',
        },
        model => {
            is => 'Genome::Model',
            doc => 'Model to build.'
        },
        build => {
            is => 'Genome::Model::Build',
            doc => 'Da build.'
        },
    ],

};

sub sub_command_sort_position { 1 }

sub help_synopsis {
    return <<EOS;
genome model build start 1234

genome model build start somename
# default values for dispatching will be either -s long -j apipe
# or come from the processing profile if available as a param

genome model build start somename -s long -j apipe
# run the server in the long queue, and jobs in the apipe queue

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

#< Execute >#
sub execute {
    my $self = shift;

    $DB::single = 1;

    # Get model
    my $model = $self->_resolve_model
        or return;

    # Check running builds, only if we are not forcing
    unless ( $self->force ) {
        $self->_verify_no_other_builds_running
            or return;
    }

    my @p;
    if ($self->data_directory) {
        push @p, data_directory => $self->data_directory;
    }

    my $server_dispatch;
    my $job_dispatch;

    if (defined $self->server_dispatch) {
        $server_dispatch = $self->server_dispatch;
    } elsif ($model->processing_profile->can('server_dispatch') && defined $model->processing_profile->server_dispatch) {
        $server_dispatch = $model->processing_profile->server_dispatch;
    } else {
        $server_dispatch = 'long';
    }

    if (defined $self->job_dispatch) {
        $job_dispatch = $self->job_dispatch;
    } elsif ($model->processing_profile->can('job_dispatch') && defined $model->processing_profile->job_dispatch) {
        $job_dispatch = $model->processing_profile->job_dispatch;
    } else {
        $job_dispatch = 'apipe';
    }

    # Create the build
    my $build = Genome::Model::Build->create(model_id => $model->id, @p);
    unless ( $build ) {
        $self->error_message(
            sprintf("Can't create build for model (%s %s)", $model->id, $model->name) 
        );
        return;
    }
    $self->build($build);

    # Launch the build
    unless (
        $build->start(
            server_dispatch => $server_dispatch,
            job_dispatch => $job_dispatch
        )
    ) {
        $self->error_message("Failed to start new build: " . $build->error_message);
        return;
    }

    printf(
        "Build (ID: %s DIR: %s) created, scheduled and launched to LSF.\nAn initialization email will be sent once the build begins running.\n",
        $build->id,
        $build->data_directory,
    );

    return 1;
}

sub _resolve_model {
    my $self = shift;

    # Make sure we got an identifier
    my $model_identifier = $self->model_identifier;
    unless ( $model_identifier ) {
        $self->error_message("No model identifier given to get model.");
        return;
    }

    my $model;
    # By id if it's an integer
    if ( $self->model_identifier =~ /^$RE{num}{int}$/ ) {
        $model = Genome::Model->get($model_identifier);
    }

    # Try by name if id wasn't an integer or didn't work
    unless ( $model ) {
        $model = Genome::Model->get(name => $model_identifier);
    }

    # Neither worked
    unless ( $model ) {
        $self->error_message("Can't get model for identifier ($model_identifier).  Tried getting as id and name.");
        return;
    }

    return $self->model($model);
}

sub _verify_no_other_builds_running {
    my $self = shift;

    my @running_builds = $self->model->running_builds;
    if ( @running_builds ) {
        $self->error_message(
            sprintf(
                "Model (%s %s) already has builds running: %s. Use the 'force' param to overirde this and start a new build.",
                $self->model->id,
                $self->model->name,
                join(', ', map { $_->id } @running_builds),
            )
        );
        return;
    } 

    return 1;
}

1;

#$HeadURL$
#$Id$
