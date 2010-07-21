package Genome::Project::Command::List;

use strict;
use warnings;

use Genome;

class Genome::Project::Command::List {
    is => 'UR::Object::Command::List',
    has => [
        subject_class_name  => {
            is_constant => 1, 
            value => 'Genome::Project' 
        },
        show => { default_value => 'id,name,external_contact_name,internal_contact_email,mailing_list,description' },
        filter => { default_value => 'status!=abandoned' },
    ],
};

sub sub_command_sort_position { 1 }

1;

