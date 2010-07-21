package Genome::InstrumentData::Command;
use strict;
use warnings;

use Genome;

class Genome::InstrumentData::Command {
    is => 'Command',
    is_abstract => 1,
    english_name => 'genome instrument_data command',
    has => [
        instrument_data => { is => 'Genome::InstrumentData', id_by => 'instrument_data_id' },
        instrument_data_id => { is => 'Integer', doc => 'identifies the instrument data by id' },
    ],
};

############################################

sub help_brief {
    return 'work with instrument data';
}

############################################

sub command_name {
    my $class = ref($_[0]) || $_[0];
    return $class->SUPER::command_name unless $class eq __PACKAGE__;
    return 'genome instrument-data';
}

sub command_name_brief {
    my $class = ref($_[0]) || $_[0];
    return $class->SUPER::command_name_brief unless $class eq __PACKAGE__;
    return 'instrument-data';
}

############################################


1;

#$HeadURL$
#$Id$
