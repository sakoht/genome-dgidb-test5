package Genome::Model::Command::InstrumentData;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::InstrumentData {
    is => 'Genome::Model::Command',
    is_abstract => 1,
    doc => "assign, list, dump instrument data related to a model",
};

sub sub_command_sort_position { 6 }

1;

#$HeadURL$
#$Id$
