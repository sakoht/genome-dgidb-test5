package Genome::Sample::Command;

use strict;
use warnings;

use Genome;

class Genome::Sample::Command {
    is => 'Command::Tree',
    doc => 'work with samples',
};

use Genome::Command::Crud;
Genome::Command::Crud->init_sub_commands(
    target_class => 'Genome::Sample',
    target_name => 'sample',
    create => { do_not_init => 1, }, # use importers
    list => { show => 'id,name,species_name,patient_common_name,common_name,tissue_label,tissue_desc,extraction_type,extraction_label,extraction_desc' },
    update => { only_if_null => 1, },
    delete => { do_not_init => 1, },
);

1;

