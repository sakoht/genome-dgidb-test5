package Genome::Model::Event::Build::ImportedVariations::NoOp;

use strict;
use warnings;
use Genome;

class Genome::Model::Event::Build::ImportedVariations::NoOp {
    is => ['Genome::Model::Event'],
};


sub execute {
    my $self = shift;
    $DB::single=1;
    return 1;

}

1;
