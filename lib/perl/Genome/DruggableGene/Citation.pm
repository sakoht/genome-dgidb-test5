package Genome::DruggableGene::Citation;

use strict;
use warnings;

use Genome;

class Genome::DruggableGene::Citation {
    is => 'UR::Object',
    id_generator => '-uuid',
    table_name => 'dgidb.citation',
    schema_name => 'dgidb',
    data_source => 'Genome::DataSource::Main',
    id_by => [
        id => {is => 'Text'},
    ],
    has => [
        source_db_name => {is => 'Text'},
        source_db_version => {is => 'Text'},
        citation => {is => 'Text'},
        base_url => {is => 'Text'},
    ],
    doc => 'Citation for druggable gene object',
};

#Hard code the front page of sources rather than keep these urls in the database
sub source_db_name_to_url {
    my $class = shift;
    my $source_db_name = shift;
    for ($source_db_name) {
        return 'http://www.drugbank.ca/' if /drugbank/i;
        return 'http://ensembl.org/index.html' if /ensembl/i;
        return 'http://www.ncbi.nlm.nih.gov/gene' if /entrez/i;
        return 'http://bidd.nus.edu.sg/group/ttd/ttd.asp' if /ttd/i;
    }
    return "http://lmgtfy.com/?q=$source_db_name";#let me google that for you
}
