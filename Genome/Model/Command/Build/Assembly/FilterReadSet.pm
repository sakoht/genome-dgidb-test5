package Genome::Model::Command::Build::Assembly::FilterReadSet;

use strict;
use warnings;

use Genome;
use Command;

class Genome::Model::Command::Build::Assembly::FilterReadSet {
    is_abstract => 1,
    is => ['Genome::Model::Event'],
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "trim the reads from a read set"
}

sub help_synopsis {
    return <<"EOS"
    genome-model build assembly filter-read-set --model-id 5 --read-set-id 10
EOS
}

sub help_detail {
    return <<"EOS"
This command is launched automatically by build assembly.

It delegates to the appropriate sub-command according to
the read_filter.
EOS
}

sub command_subclassing_model_property {
    return 'read_filter_name';
}

sub should_bsub { 1;}

1;

