package Genome::InstrumentData::Command::Align::Bwa;

use strict;
use warnings;

use Genome;

class Genome::InstrumentData::Command::Align::Bwa {
    is => ['Genome::InstrumentData::Command::Align'],
    has_constant => [
        aligner_name                    => { value => 'bwa' },
    ],
    doc => 'align instrument data using BWA (see http://maq.sourceforge.net)',
};

sub help_synopsis {
return <<EOS
FIXME
EOS
}

sub help_detail {
return <<EOS
Launch the bwa aligner in a standard way and produce results ready for the genome modeling pipeline.

See http://maq.sourceforge.net.
EOS
}


1;

