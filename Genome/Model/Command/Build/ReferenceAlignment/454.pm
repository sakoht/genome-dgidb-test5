package Genome::Model::Command::Build::ReferenceAlignment::454;

use strict;
use warnings;
use Genome;

class Genome::Model::Command::Build::ReferenceAlignment::454 {
    is => 'Genome::Model::Command::Build::ReferenceAlignment',
    has => [],
 };

sub sub_command_sort_position { 40 }


sub help_brief {
    "postprocess any alignments generated by a model which have not yet been added to the full assembly"
}

sub help_synopsis {
    return <<"EOS"
genome-model build mymodel 
EOS
}

sub help_detail {
    return <<"EOS"
One build of a given reference-alignment model.
EOS
}

sub subordinate_job_classes {
    my @step1 =  ('Genome::Model::Command::AddReads::MergeAlignments');
    my @step2 =  ('Genome::Model::Command::AddReads::UpdateGenotype');
    my @step3 =  ('Genome::Model::Command::AddReads::FindVariations'),
    my @step4 =  ('Genome::Model::Command::AddReads::PostprocessVariations', 'Genome::Model::Command::AddReads::AnnotateVariations');
    
    return (\@step1, \@step2, \@step3, \@step4);
}

sub execute {
    my $self = shift;

    $DB::single = $DB::stopper;

    my @sub_command_classes = $self->subordinate_job_classes;

    my $model = Genome::Model->get($self->model_id);
    my @subreferences_names = grep {$_ ne "all_sequences" } $model->get_subreference_names(reference_extension=>'bfa');

    unless (@subreferences_names > 0) {
        @subreferences_names = ('all_sequences');
    }

    foreach my $ref (@subreferences_names) { 
    my $prior_event_id = undef;
        foreach my $command_classes ( @sub_command_classes ) {
            
            my $command;
            for my $command_class (@{$command_classes}) {  
                $command = $command_class->create(
                    model_id => $self->model_id, 
                    ref_seq_id=>$ref,
                    prior_event_id => $prior_event_id,
                    parent_event_id => $self->id,
                );
                $command->parent_event_id($self->id);
                $command->event_status('Scheduled');
                $command->retry_count(0);
            }
            #clearly this will not work well if the pipeline wanted to come back together after a fork...
            #don't cry about it if it happens
            $prior_event_id = $command->id;
        }
    }

    return 1; 
}

sub extend_last_execution {
    my ($self) = @_;

    # like execute, but get the existing steps, see which ones never got executed, and generates those.

    my @sub_command_classes = $self->subordinate_job_classes;

    my $model = Genome::Model->get($self->model_id);
    my @subreferences_names = grep {$_ ne "all_sequences" } $model->get_subreference_names(reference_extension=>'bfa');

    unless (@subreferences_names > 0) {
        @subreferences_names = ('all_sequences');
    }

    my @new_events;    
    foreach my $ref (@subreferences_names) { 
        my $prior_event_id = undef;
        foreach my $command_class ( @sub_command_classes ) {
            my $command = $command_class->get(
                model_id => $self->model_id, 
                ref_seq_id => $ref,
                parent_event_id => $self->id,
            );

            unless ($command) {
                $command = $command_class->create(
                    model_id => $self->model_id, 
                    ref_seq_id=>$ref,
                    prior_event_id => $prior_event_id,
                    parent_event_id => $self->id,
                );
                unless ($command) {
                    die "Failed to create command object: $command_class!" . $command_class->error_message;
                }
                push @new_events, $command;
                $command->parent_event_id($self->id);
                $command->event_status('Scheduled');
                $command->retry_count(0);
            }

            $prior_event_id = $command->id;
        }
    }

    return @new_events; 
}

sub _get_sub_command_class_name{
  return __PACKAGE__; 
}

1;

