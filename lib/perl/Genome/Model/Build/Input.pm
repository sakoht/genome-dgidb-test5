package Genome::Model::Build::Input;

use strict;
use warnings;

use Genome;
class Genome::Model::Build::Input {
    type_name => 'genome model build input',
    table_name => 'GENOME_MODEL_BUILD_INPUT',
    id_by => [
        build_id         => { is => 'NUMBER', len => 11, implied_by => 'build' },
        value_class_name => { is => 'VARCHAR2', len => 255 },
        value_id         => { is => 'VARCHAR2', len => 1000, implied_by => 'value' },
        name             => { is => 'VARCHAR2', len => 255 },
    ],
    has => [
        model      => { is => 'Genome::Model', via => 'build' },
        model_name => { via => 'model', to => 'name' },
        build      => { is => 'Genome::Model::Build', id_by => 'build_id', constraint_name => 'GMBI_GMB_FK' },
        value      => { is => 'UR::Object', id_by => 'value_id', id_class_by => 'value_class_name' },
        value_model => { is => 'Genome::Model', id_by => 'value_id' },
        value_build => { is => 'Genome::Model::Build', id_by => 'value_id' },
        value_inst_data => { is => 'Genome::InstrumentData', id_by => 'value_id' },
    ],
    has_optional => [
        filter_desc => { 
            is => 'Text',
            valid_values => [ 'forward-only', 'reverse-only', undef ],
            doc => 'Filter to apply on the input value.'
        },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

1;

#$HeadURL$
#$Id$
