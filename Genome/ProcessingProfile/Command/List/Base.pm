package Genome::ProcessingProfile::Command::List::Base;

use strict;
use warnings;

use Genome;
#use Command; 
#use Data::Dumper;
#use Genome::ProcessingProfile;

class Genome::ProcessingProfile::Command::List::Base {
    is => 'UR::Object::Command::List',
    is_abstract => 1,
    has => [
        subject_class_name  => {
            is_constant => 1, 
            value => 'Genome::ProcessingProfile' 
        },
        show => { default_value => 'id,type_name,name' },
    ],
    doc => 'list processing profiles by type'
};

sub execute {
    my $self = shift;
    # it's actually faster to load everything in one shot than to query carefully
    my @pp = Genome::ProcessingProfile::Param->get();
    my @p = Genome::ProcessingProfile->get();
    return $self->SUPER::_execute_body(@_);
}

1;

