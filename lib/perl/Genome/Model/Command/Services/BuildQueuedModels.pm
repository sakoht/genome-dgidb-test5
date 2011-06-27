package Genome::Model::Command::Services::BuildQueuedModels;

use strict;
use warnings;

use Genome;
use Genome::Model::Build::Command::Start;

use POSIX qw(ceil);

class Genome::Model::Command::Services::BuildQueuedModels {
    is => 'Genome::Command::Base',
    doc => "Build queued models.",
    has_optional => [
        max_scheduled_builds => {
            is => 'Integer',
            default => 50,
        },
        channels => {
            is => 'Integer',
            default => 1,
            doc => 'number of "channels" to parallelize models by',
        },
        channel => {
            is => 'Integer',
            default => 0,
            doc => 'zero-based channel to use',
        },
        builds => {
            is => 'Genome::Model::Build',
            is_many => 1,
            is_output => 1,
        },
        _builds_started => {
            is => 'Integer',
            default => 0,
        },
        _total_count => {
            is => 'Integer',
            default => 0,
        },
        _create_params => {
            is => 'Hash',
            default => {},
        },
        _start_params => {
            is => 'Hash',
            default => {},
        },
        _errors => {
            is => 'Text',
            is_many => 1,
        },
    ],
};

sub help_synopsis {
    return <<EOS;
genome model services build-queued-models
EOS
}

sub help_detail {
    return <<EOS;
Builds queued models.
EOS
}

sub execute {
    my $self = shift;

    unless ($self->channel < $self->channels) {
        die $self->error_message('--channel must be less than --channels');
    }

    my $lock_resource = '/gsc/var/lock/genome_model_services_builed_queued_models_' . $self->channel . '_' . $self->channels;

    my $lock = Genome::Sys->lock_resource(resource_lock => $lock_resource, max_try => 1);
    unless ($lock) {
        $self->error_message("Could not lock, another instance of BQM must be running.");
        return;
    }

    my $context = UR::Context->current;
    $context->add_observer(
        aspect => 'commit',
        callback => sub{ Genome::Sys->unlock_resource(resource_lock => $lock) },
    );

    my $max_builds_to_start = $self->num_builds_to_start;
    unless ($max_builds_to_start) {
        $self->status_message("There are already " . $self->max_scheduled_builds . " builds scheduled.");
        return 1;
    }
    $self->status_message("Will try to start up to $max_builds_to_start builds.");

    my @iterator_params = (
        # prioritize genotype microarray over other builds because their
        # runtime is so short and are frequently prerequisite for other builds
        {build_requested => '1', type_name => 'genotype microarray'}, 
        {build_requested => '1'},
    );

    ITERATOR:
    while (my $iterator_params = shift @iterator_params) {
        my $models = Genome::Model->create_iterator(%{$iterator_params});

        MODEL:
        while (my $model = $models->next) {
            next MODEL unless ($model->id % $self->channels == $self->channel);

            if ($self->_builds_started >= $max_builds_to_start){
                $self->status_message("Already started max builds (" . $self->_builds_started . "), quitting...");
                last ITERATOR; 
            }

            $self->_total_count($self->_total_count + 1);
            Genome::Model::Build::Command::Start::create_and_start_build($self, $model);
        }
    }

    my $expected_count = ($max_builds_to_start > $self->_total_count ? $self->_total_count : $max_builds_to_start);
    $self->display_command_summary_report($self->_total_count, $self->_errors);
    $self->status_message('   Expected: ' . $expected_count);

    return !scalar($self->_errors);
}


sub num_builds_to_start {
    my $self = shift;
    
    my $scheduled_builds = Genome::Model::Build->create_iterator(
        run_by => Genome::Sys->username,
        status => 'Scheduled',
    );
    
    my $scheduled_build_count = 0;
    while ($scheduled_builds->next && ++$scheduled_build_count <= $self->max_scheduled_builds) { 1; }
    
    my $max_per_channel = int($self->max_scheduled_builds / $self->channels);
    if ($scheduled_build_count >= $self->max_scheduled_builds) {
        return 0;
    }
    elsif (($scheduled_build_count + $max_per_channel) > $self->max_scheduled_builds) {
        return ceil($max_per_channel / $self->channels);
    }
    else {
        return $max_per_channel;
    }
}


1;
