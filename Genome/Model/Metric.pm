package Genome::Model::Metric;

use strict;
use warnings;

use Genome;

class Genome::Model::Metric {
    type_name => 'genome model metric',
    table_name => 'GENOME_MODEL_METRIC',
    id_by => [
        build => { is => 'Genome::Model::Build', id_by => 'build_id', constraint_name => 'GMM_BI_FK' },
        value => { is => 'VARCHAR2', len => 1000, column_name => 'METRIC_VALUE' },
        name  => { is => 'VARCHAR2', len => 100, column_name => 'METRIC_NAME' },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

1;

