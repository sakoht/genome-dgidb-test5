package Genome::Model::Metric;

use strict;
use warnings;

use Genome;

class Genome::Model::Metric {
    type_name => 'genome model metric',
    table_name => 'GENOME_MODEL_METRIC',
    id_by => [
        model => { is => 'Genome::Model', id_by => 'model_id', constraint_name => 'GMM_GM_FK' },
        name  => { is => 'VARCHAR2', len => 100, column_name => 'METRIC_NAME' },
    ],
    has => [
        value => { is => 'VARCHAR2', len => 1000, column_name => 'METRIC_VALUE', is_optional => 1 },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

1;

