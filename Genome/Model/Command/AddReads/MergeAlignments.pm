package Genome::Model::Command::AddReads::MergeAlignments;

use strict;
use warnings;

use above "Genome";
use Command; 

class Genome::Model::Command::AddReads::MergeAlignments {
    is => ['Genome::Model::Command::DelegatesToSubcommand::WithRefSeq'],
};

sub sub_command_sort_position { 50 }

sub help_brief {
    "Merge any accumulated alignments on a model";
}

sub help_synopsis {
    return <<"EOS"
    genome-model add-reads merge-alignments --model-id 5  --ref-seq-id all_sequences
EOS
}

sub help_detail {
    return <<"EOS"
This command is launched automatically by "postprocess alignments".  

It delegates to the appropriate sub-command for the aligner
specified in the model.
EOS
}

sub command_subclassing_model_property {
    return 'read_aligner_name';
}

sub is_not_to_be_run_by_add_reads {
    return 1;
}
  
1;

