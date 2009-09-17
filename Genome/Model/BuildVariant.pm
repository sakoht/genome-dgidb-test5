package Genome::Model::Build::Variant;

use strict;
use warnings;

use Genome;
class Genome::Model::Build::Variant {
    type_name => 'genome model build variant',
    table_name => 'GENOME_MODEL_BUILD_VARIANT',
    er_role => 'bridge',
    id_by => [
        build_id   => { is => 'NUMBER', len => 10 },
        variant_id => { is => 'NUMBER', len => 10 },
    ],
    has => [
        build   => { is => 'Genome::Model::Build', id_by => 'build_id', constraint_name => 'GMBV_GMB_FK' },
        variant => { is => 'Genome::Model::Variant', id_by => 'variant_id', constraint_name => 'GMBV_GMV_FK' },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

1;
