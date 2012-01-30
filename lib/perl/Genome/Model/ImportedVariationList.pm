package Genome::Model::ImportedVariationList;

use strict;
use warnings;

use Genome;

class Genome::Model::ImportedVariationList {
    is => 'Genome::ModelDeprecated',
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

sub dbsnp_model_for_reference {
    my ($class, $reference) = @_;
    my @models = $class->get(name => "dbSNP-" . $reference->name);
    if (!@models and defined $reference->coordinates_from) {
        @models = $class->get(name => "dbSNP-" . $reference->coordinates_from->name);
    }
    return if @models != 1 or !$models[0]->reference->is_compatible_with($reference);
    return $models[0];
}

sub dbsnp_build_for_reference {
    my ($class, $reference) = @_;
    my $model = $class->dbsnp_model_for_reference($reference);
    return $model->last_complete_build if defined $model;
    return;
}
1;

