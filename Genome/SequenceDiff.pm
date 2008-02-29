package Genome::SequenceDiff;

use strict;
use warnings;

use Genome;
class Genome::SequenceDiff {
    type_name => 'sequence diff',
    table_name => 'SEQUENCE_DIFF',
    id_by => [
        diff_id => { is => 'NUMBER', len => 10 },
    ],
    has => [
        description => { is => 'VARCHAR2', len => 256, is_optional => 1 },
        from_path   => { is => 'VARCHAR2', len => 256, is_optional => 1 },
        to_path     => { is => 'VARCHAR2', len => 256, is_optional => 1 },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

1;
