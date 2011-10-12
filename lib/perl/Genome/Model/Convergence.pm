package Genome::Model::Convergence;

use strict;
use warnings;

use Genome;

use Array::Compare;

class Genome::Model::Convergence {
    is  => 'Genome::Model',
    has => [
        group_id => {
            is => 'Integer',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'group', value_class_name => 'Genome::ModelGroup' ],
            doc => 'The id for the ModelGroup for which this is the Convergence model',
            
            is_mutable => 1,
        },
        group => {
            is => 'Genome::ModelGroup',
            id_by => 'group_id',
            doc => 'The ModelGroup for which this is the Convergence model',
        },
        members => {
            is => 'Genome::Model',
            via => 'group',
            is_many => 1,
            to => 'models',
            doc => 'Models that are members of this Convergence model.',
        },
        map({
            $_ => {
                via => 'processing_profile',
            }
        } Genome::ProcessingProfile::Convergence->params_for_class),
    ],
    doc => <<EODOC
This model type attempts to use the data collected across many samples to generalize and summarize
knowledge about the group as a whole.
EODOC
};


sub schedule_rebuild {
    my $self = shift;
    
    unless($self->auto_build_alignments){
        $self->status_message('auto_build_alignments is false for this convergence model');
        return 1;
    }

    unless($self->build_needed) {
        $self->status_message('Skipping convergence rebuild--not needed.');
        return 1;
    }

    my @builds_to_abandon = $self->builds(status => ['Scheduled', 'Running']);
    if (@builds_to_abandon){
        Genome::Model::Build::Command::Abandon->execute(builds => [@builds_to_abandon]);

        my @failed_to_abandon = grep{ $_->status ne 'Abandoned' } @builds_to_abandon;
        if (@failed_to_abandon) {
            $self->warning_message("Failed to abandon scheduled/running convergence builds: " . join(", ", map { $_->id } @failed_to_abandon) . ".");
        }
    }

    $self->build_requested(1);
    $self->status_message('Convergence rebuild requested.');

    return 1;
}

# Updates the convergence model immediately prior to a build starting. In this case, makes sure
# that the convergence model's subject is correct.
sub check_for_updates {
    my $self = shift;
    my $subject = $self->subject;
    my $group_subject = $self->group->infer_group_subject;

    if ($group_subject->class eq $subject->class and $group_subject->id eq $subject->id) {
        return 1;
    }

    $self->subject_id($group_subject->id);
    $self->subject_class_name($group_subject->class);
    return 1;
}

sub build_needed {
    my $self = shift;

    my @group_members = $self->members;
    my @b = Genome::Model::Build->get(model_id => [map($_->id, @group_members)], '-hint' => ['the_master_event']); #preload in one query

    my @potential_members = grep(defined $_->last_complete_build, @group_members);
    unless(scalar @potential_members) {
        #$self->status_message('Skipping convergence rebuild--no succeeded builds found among members.');
        return;
    }

    #Check to see if our last build already used all the same builds as we're about to
    if($self->last_complete_build) {
        my $last_build = $self->last_complete_build;

        my @last_members = $last_build->members;

        my $comparator = Array::Compare->new;
        if($comparator->perm(\@last_members, \@potential_members)) {
            #$self->status_message('Skipping convergence rebuild--list of members that would be included is identical to last build.');
            return;

            #Potentially if some of the underlying builds in the $build->all_subbuilds_closure have changed, a rebuild might be desired
            #For now this will require a manual rebuild (`genome model build start`)
        }
    }

    return 1;
}

1;
