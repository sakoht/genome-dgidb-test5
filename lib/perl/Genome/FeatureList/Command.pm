package Genome::FeatureList::Command;

use strict;
use warnings;

use Genome;


class Genome::FeatureList::Command {
    is => 'Genome::Command::Base',
    has => [
        feature_list => {
            is => 'Genome::FeatureList',
            shell_args_position => 1,
        },
    ],
};

sub help_brief {
    "Commands to interact with feature-lists.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
 gmt feature-list ...    
EOS
}

sub help_detail {                           
    return <<EOS 
A collection of commands to interact with feature-lists.
EOS
}

1;
