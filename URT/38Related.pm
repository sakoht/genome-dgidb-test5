package URT::38Related;

use URT;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => 'URT::38Related',
    id_by => [ related_id => { is => 'Integer' }, ],
    has => [
        related_value   => { is => 'String' },
        primary_objects => { is => 'URT::38Primary', reverse_id_by => 'related_object', is_many => 1 },
        primary_values  => { via => 'primary_objects', to => 'primary_value', is_many => 1},
    ],
    data_source => 'URT::DataSource::SomeSQLite2',
    table_name => 'related',
);
1;

