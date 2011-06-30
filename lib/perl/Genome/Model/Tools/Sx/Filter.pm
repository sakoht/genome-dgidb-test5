package Genome::Model::Tools::Sx::Filter;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';

class Genome::Model::Tools::Sx::Filter {
    is  => 'Genome::Model::Tools::Sx',
    is_abstract => 1,
};

sub help_brief {
    return 'Filter sequences';
}

sub execute {
    my $self = shift;

    my $init = $self->_init;
    return if not $init;

    my $reader = $self->_reader;
    my $writer = $self->_writer;

    my @filters = $self->_create_filters;
    return if not @filters;

    SEQS: while ( my $seqs = $reader->read ) {
        for my $filter ( @filters ) {
            next SEQS if not $filter->($seqs);
        }
        $writer->write($seqs);
    }

    return 1;
}

1;

