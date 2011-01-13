package Genome::Library; 

use strict;
use warnings;
use Genome;

class Genome::Library {
    is => ['Genome::Notable'],
    table_name => 'GSC.LIBRARY_SUMMARY',
    id_by => [
        library_id          => { is => 'Number', len => 20, column_name => 'LIBRARY_ID', },
    ],
    has => [
        name                => { is => 'Text', len => 64, column_name => 'FULL_NAME' },
        sample              => { is => 'Genome::Sample', id_by => 'sample_id' },
        sample_name         => { is => 'Text', via => 'sample', to => 'name' },
    ],
    has_optional => [
        fragment_size_range     => { is => 'Text', len => 64, 
                                    column_name => 'LIBRARY_INSERT_SIZE',
                                    doc => 'intended size range of fragments from library construction' },
        taxon_id                => { is => 'Number', via => 'sample', },
        taxon                   => { is => 'Genome::Taxon', via => 'sample', },
        species_name            => { is => 'Text', via => 'taxon', },
        protocol_name           => { is_transient => 1, is => 'Text', },
    ],
    data_source => 'Genome::DataSource::GMSchema',
};

sub __display_name__ {
    return $_[0]->name.' ('.$_[0]->id.')';
}

1;

