package Genome::Model::Command::Build::ReferenceAlignment::UpdateGenotype;


#REVIEW fdu
#Fix out-of-date help_brief, help_synopsis, and help_detail


use strict;
use warnings;

use Genome;

class Genome::Model::Command::Build::ReferenceAlignment::UpdateGenotype {
    is => ['Genome::Model::Event'],
};

sub sub_command_sort_position { 70 }

sub help_brief {
    "add reads from all or part of an instrument run to the model"
}

sub help_synopsis {
    return <<"EOS"
    genome-model add-reads update-genotype --model-id 5 --ref-seq-id all_sequences
EOS
}

sub help_detail {
    return <<"EOS"
This command is launched automatically by "add reads".  

It delegates to the appropriate sub-command for the genotyper
specified in the model.
EOS
}

sub command_subclassing_model_property {
    return 'genotyper_name';
}

1;

