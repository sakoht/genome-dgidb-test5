
# Rename the final word in the full class name <---
package Genome::Model::Command::Updaate::AddReads;

use strict;
use warnings;

use UR;
use Command;

UR::Object::Class->define(
    class_name => __PACKAGE__,
    is => 'Command',
);

sub help_brief {
    "add reads to a genome model"
}

sub help_detail {                           # This is what the user will see with --help <---
    return <<EOS 


EOS
}

1;

