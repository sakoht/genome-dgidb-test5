package Genome::Model::RefSeq;

use strict;
use warnings;

use Genome;
class Genome::Model::RefSeq {
    type_name => 'genome model ref seq',
    table_name => 'GENOME_MODEL_REF_SEQ',
    id_by => [
        model        => { is => 'Genome::Model', id_by => 'model_id', constraint_name => 'GMRS__GM_PK' },
        ref_seq_name => { is => 'VARCHAR2', len => 64 },
    ],
    has => [
        ref_seq_id                     => { is => 'NUMBER', len => 10, is_optional => 1 },
        variation_positions            => { is => 'Genome::Model::VariationPosition', reverse_id_by => 'model_refseq', is_many => 1 },
        variation_position_read_depths => { via => 'variation_positions', to => 'read_depth', is_many => 1 },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

1;
