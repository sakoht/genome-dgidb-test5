package Genome::Model::ImportedVariations;

use strict;
use warnings;

use Genome;
use File::Basename;
use Sort::Naturally;
use IO::File;

class Genome::Model::ImportedVariations{
    is => 'Genome::Model',
    has => [
        input_format    => { via => 'processing_profile' },
        instrument_type => { via => 'processing_profile' },
    ],
};

sub imported_variations_directory {
    my $self = shift;
    return $self->data_directory."/ImportedVariations";
}


1;

