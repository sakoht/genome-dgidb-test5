#!/gsc/bin/perl

use strict;
use warnings;
use above "Genome";

use Test::More tests => 9;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{USE_DUMMY_AUTOGENERATED_IDS} = 1;

use_ok('Genome::DruggableGene::GeneNameReport');

my ($entrez_gene_name_reports, $intermediate_gene_name_reports) = Genome::DruggableGene::GeneNameReport->convert_to_entrez('AKR1D1');
ok(%{$entrez_gene_name_reports}, 'Found entrez_gene_symbol: AKR1D1');
ok(!$intermediate_gene_name_reports, 'No intermediate_gene_name_reports for AKR1D1');

($entrez_gene_name_reports, $intermediate_gene_name_reports) = Genome::DruggableGene::GeneNameReport->convert_to_entrez('ENTRZ_G26157');
ok(%{$entrez_gene_name_reports}, 'Found entrez_gene_id: 26157');
ok(!$intermediate_gene_name_reports, 'No intermediate_gene_name_reports for 26157');

($entrez_gene_name_reports, $intermediate_gene_name_reports) = Genome::DruggableGene::GeneNameReport->convert_to_entrez('ENSG00000126550');
ok(%{$entrez_gene_name_reports}, 'Found ensembl_id: ENSG00000204227');
ok(!$intermediate_gene_name_reports, 'No intermediate_gene_name_reports for ENSG00000204227');

($entrez_gene_name_reports, $intermediate_gene_name_reports) = Genome::DruggableGene::GeneNameReport->convert_to_entrez('P51857');
ok(%{$entrez_gene_name_reports}, 'Found uniprot_id: P51857');
ok(%{$intermediate_gene_name_reports}, 'Intermediate_gene_name_reports for P51857');

#($entrez_gene_name_reports, $intermediate_gene_name_reports) = Genome::DruggableGene::GeneNameReport->convert_to_entrez("HOR5'Beta6");
#ok(%{$entrez_gene_name_reports}, "Found: HOR5'Beta6");
#ok(!$intermediate_gene_name_reports, "No intermediate_gene_name_reports for HOR5'Beta6");
