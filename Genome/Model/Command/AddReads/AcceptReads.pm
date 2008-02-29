
package Genome::Model::Command::AddReads::AcceptReads;

use strict;
use warnings;

use above "Genome";
use Command; 

class Genome::Model::Command::AddReads::AcceptReads {
    is => ['Genome::Model::Command::DelegatesToSubcommand::WithRun'],
};

sub sub_command_sort_position { 30 }

sub help_brief {
    "add reads from all or part of an instrument run to the model"
}

sub help_synopsis {
    return <<"EOS"
    genome-model add-reads accept-reads --model-id 5 --run-id 10
EOS
}

sub help_detail {
    return <<"EOS"
This command is launched automatically by "add reads".  

It delegates to the appropriate sub-command according to 
the model's sequencing platform.
EOS
}

sub sub_command_delegator {
    my $self = shift;

    my $model = Genome::Model->get($self->model_id);
    return unless $model;

    return $model->genotyper_name;
}


1;

