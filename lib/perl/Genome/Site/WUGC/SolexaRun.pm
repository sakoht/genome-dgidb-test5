package Genome::Site::WUGC::SolexaRun;
use strict;
use warnings;
use Genome;

class Genome::Site::WUGC::SolexaRun { 
    table_name => 'gsc.solexa_run@oltp flow_cell',
    id_by => 'er_id',
    has => [
        'name' => { column_name => 'flow_cell_id' }, 
    ],
    data_source => 'Genome::DataSource::GMSchema'
};


1;

