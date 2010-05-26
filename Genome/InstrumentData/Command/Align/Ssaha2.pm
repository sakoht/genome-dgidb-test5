package Genome::InstrumentData::Command::Align::Ssaha2;

#REVIEW fdu
#limited use, removable, see REVIEW in base class Align.pm

use strict;
use warnings;

use Genome;

class Genome::InstrumentData::Command::Align::Ssaha2 {
    is => ['Genome::InstrumentData::Command::Align'],
    has_constant => [
        aligner_name                    => { value => 'ssaha2' },
    ],
    has_param => [
        version                 => { default_value => '0.5.5'},
    ],
    doc => 'align instrument data using SSAHA2'
};

sub help_synopsis {
return <<EOS
FIXME
EOS
}

sub help_detail {
return <<EOS
Launch the aligner in a standard way and produce results ready for the genome modeling pipeline.

EOS
}


1;

