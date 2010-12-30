package Genome::Model::ImportedVariationList;

use strict;
use warnings;

use Genome;

class Genome::Model::ImportedVariationList {
    is => 'Genome::Model',
    has => [
        reference_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'reference', value_class_name => 'Genome::Model::Build::ImportedReferenceSequence' ],
            is_many => 0,
            is_mutable => 1,
            doc => 'reference sequence to align against'
        },
        reference => {
            is => 'Genome::Model::Build::ImportedReferenceSequence',
            id_by => 'reference_id',
        },
    ],
};

1;

