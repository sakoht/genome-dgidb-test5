package Genome::Site::WUGC::DNAResource;
use strict;
use warnings;
use Genome;

class Genome::Site::WUGC::DNAResource { 
    table_name => 'GSC.DNA_RESOURCE@oltp dna_resource',
    id_by => 'dr_id',
    has => [
        'name' => { column_name => 'dna_resource_prefix' }, 
    ],
    data_source => 'Genome::DataSource::GMSchema'
};


1;

