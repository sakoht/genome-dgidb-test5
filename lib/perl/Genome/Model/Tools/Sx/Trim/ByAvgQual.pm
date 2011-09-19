package Genome::Model::Tools::Sx::Trim::ByAvgQual;

use strict;
use warnings;

use Genome;            

use Regexp::Common;

class Genome::Model::Tools::Sx::Trim::ByAvgQual {
    is => 'Genome::Model::Tools::Sx',
    has => [
        quality => {
            is => 'Integer',
            doc => 'The minimum quality of the entire seqeunce. Bases will be trimmed from the end until quality reaches this average.',
        },    
     ],
};

sub help_brief {
    return 'Trim until sequence avg qual is above the threshold';
}

sub help_detail {
    return "Trim one base at a time from the 3' end until the average quality of the sequence reaches or exceeds the quality threshold. If the average qualtity of the sequence does not reach or execeed the threshold, the sequence and quality will be set to empty strings. Emtpy sequences are not removed or filtered."; 
}

sub __errors__ {
    my $self = shift;
    my @errors = $self->SUPER::__errors__(@_);
    return @errors if @errors;
    if ( $self->quality !~ /^$RE{num}{int}$/ or $self->quality < 1 ) {
        push @errors, UR::Object::Tag->create(
            type => 'invalid',
            properties => [qw/ length /],
            desc => 'Quality is not a integer greater than 0 => '.$self->quality,
        );
    }
    return @errors;
}

sub _eval_seqs {
    my ($self, $seqs) = @_;

    SEQ: for my $seq (@$seqs) {
        while ( Genome::Model::Tools::Sx::Base->calculate_average_quality($seq->{qual}) < $self->quality ) {
            chop $seq->{seq};
            chop $seq->{qual};
            next SEQ if length($seq->{seq}) == 0;
        }
    }

    return 1;
}

1;

