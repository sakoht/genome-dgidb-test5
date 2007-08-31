
package Genome::Model::Command::List;

use strict;
use warnings;

use UR;
use Command; 
use Data::Dumper;

UR::Object::Class->define(
    class_name => __PACKAGE__,
    is => 'Command',
);

sub help_brief {
    "list information about genome models and available runs"
}

sub help_synopsis {
    return <<"EOS"
genome-model list 
EOS
}

sub help_detail {
    return <<"EOS"
Lists all known genome models.
EOS
}

sub execute {

}

1;

