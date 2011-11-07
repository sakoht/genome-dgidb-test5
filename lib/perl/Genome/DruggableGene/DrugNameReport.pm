package Genome::DruggableGene::DrugNameReport;

use strict;
use warnings;

use Genome;

class Genome::DruggableGene::DrugNameReport {
    is => 'Genome::Searchable',
    id_generator => '-uuid',
    table_name => 'drug_name_report',
    schema_name => 'subject',
    data_source => 'Genome::DataSource::Main',
    id_by => [
        id => { is => 'Text'},
    ],
    has => [
        name => { is => 'Text'},
        nomenclature => { is => 'Text'},
        source_db_name => { is => 'Text'},
        source_db_version => { is => 'Text'},
        description => {
            is => 'Text',
            is_optional => 1,
        },
        drug_name_report_associations => {
            is => 'Genome::DruggableGene::DrugNameReportAssociation',
            reverse_as => 'drug_name_report',
            is_many => 1,
        },
        drug_name_report_category_associations => {
            is => 'Genome::DruggableGene::DrugNameReportCategoryAssociation',
            reverse_as => 'drug_name_report',
            is_many => 1,
        },
        drug_gene_interaction_reports => {
            is => 'Genome::DruggableGene::DrugGeneInteractionReport',
            reverse_as => 'drug_name_report',
            is_many => 1,
        },
        gene_name_reports => {
            is => 'Genome::DruggableGene::GeneNameReport',
            via => 'drug_gene_interaction_reports',
            to => 'gene_name_report',
            is_many => 1,
        }
    ],
    doc => 'Claim regarding the name of a drug',
};

sub __display_name__ {
    my $self = shift;
    return $self->name . '(' . $self->source_db_name . ' ' . $self->source_db_version . ')';
}

1;
