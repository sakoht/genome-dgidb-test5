package Genome::Model::Tools::Sx::SamReader;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Sx::SamReader {
    is => 'Genome::Model::Tools::Sx::SeqReader',
};

sub read {
    my $self = shift;

    my $line = $self->{_file}->getline;
    return if not defined $line;
    chomp $line;

    my @tokens = split(/\s+/, $line);

    my $seq = {
        id => $tokens[0],
        seq => $tokens[9],
        qual => $tokens[10],
        flag => $tokens[1],
    };

    for my $attr (qw/ id seq qual /) {
        Carp::confess("No $attr on line: $line") if not defined $seq->{$attr};
    }

    if ( $seq->{flag} & 0x40 ) { # forward
        $seq->{id} .= '/1';
    }
    elsif ( $seq->{flag} & 0x80 ) { # forward
        $seq->{id} .= '/2';
    }
    else {
        Carp::confess('Invalid bit flag in sequence: '.Data::Dumper::Dumper($seq));
    }

    if ( length $seq->{seq} != length $seq->{qual} ) {
        Carp::confess('Length of sequence ('.length($seq->{seq}).') and quality ('.length($seq->{qual}).') does not match. Line: '.$line);
    }

    return $seq;
}

1;

