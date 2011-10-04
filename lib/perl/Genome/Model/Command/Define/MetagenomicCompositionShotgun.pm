package Genome::Model::Command::Define::MetagenomicCompositionShotgun;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Define::MetagenomicCompositionShotgun {
    is => 'Genome::Model::Command::Define::Base',
    has => [
        _model_class => { value => 'Genome::Model::MetagenomicCompositionShotgun', },
    ],
};

1;

