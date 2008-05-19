package Genome::Model::Command::Services::JobMonitor;

use strict;
use warnings;

use above "Genome";

class Genome::Model::Command::Services::JobMonitor {
    is => 'Command',
    has => [
        dispatcher => { is => 'String', is_optional => 0 },
    ]
};

sub help_brief {
    return <<EOS
executes scheduled steps, rescues failed jobs
EOS
}

sub help_synopsis {
    return <<EOS
genome-model services job-monitor
EOS
}

sub help_detail {
    return <<EOS 
Monitors and possibly launches jobs.
EOS
}

sub context {
    UR::Context->get_current();
}

sub execute {
    my $self = shift;

    unless ($< == 10102) {
        $self->error_message("This module should only be run by via cron.");
        return;
    }

    $DB::single = 1;

    no warnings;
    
    my @launchable_events =
        grep { $_->event_type !~ /accept/ } 
        sort { ($a->model_id <=> $b->model_id) || ($a->date_scheduled <=> $b->date_scheduled) }
        Genome::Model::Event->get(
            event_status => 'Scheduled', # how did this get an uppercase everywhere?
            lsf_job_id => undef,
            ref_seq_id => undef,
            #-order_by => ['model_id','date_scheduled'],
        );

    $DB::single = 1;

    $self->_launch_events(@launchable_events);

    @launchable_events = 
        sort { ($a->model_id <=> $b->model_id) || ($a->date_scheduled <=> $b->date_scheduled) }
        Genome::Model::Event->get(
            event_status => 'Scheduled', # how did this get an uppercase everywhere?
            lsf_job_id => undef,
            run_id => undef,
            #-order_by => ['model_id','-ref_seq_id'],
        );

    $self->_launch_events(@launchable_events);

    return 1;
}

sub _launch_events {
    my $self = shift;
    my @launchable_events = @_;
    
    my $last_event;
    while (my $event = shift @launchable_events) {
        $self->status_message(
            join("\t", 
                $event->id,
                $event->event_type,
                $event->read_set->full_path,
            )
        );
        if ($last_event) {
            no warnings;
            if (
                $event->model_id != $last_event->model_id
                or $event->ref_seq_id ne $last_event->ref_seq_id
                or $event->read_set_id ne $last_event->read_set_id
            ) {
                $last_event = undef;
            }
        }
        
        
        if ($self->dispatcher eq "inline") {
            my $result = $event->execute();
            $event->date_completed(UR::Time->now);
            if ($result) {
                $event->event_status("Succeeded");
            }
            else {
                $event->event_status("Failed");
            }
            
        }
        elsif ($self->dispatcher eq "lsf") {
            my $last_bsub_job_id = $event->execute_with_bsub(last_event => $last_event);
            unless ($last_bsub_job_id) {
                $self->error_message("Error running bsub for event " . $event->id);
                # skip on to the events for the next model
                $last_event = $event;
                while ($event->model_id eq $last_event->model_id) {
                    $self->warning_message("Skipping event " . $event->id . " due to previous error.");
                    $event = shift @launchable_events;
                    last if not defined $event;
                }
                redo;
            }
            $event->lsf_job_id($last_bsub_job_id);
        }
        else {
            $self->error_message("Unknown dispatcher: " . (defined $self->dispatcher ? $self->dispatcher : ''));
            return;
        }
        
        $self->context->commit;
        
        $last_event  = $event;
    }
}

1;
