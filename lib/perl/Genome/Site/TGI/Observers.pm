package Genome::Site::TGI::Observers;

use strict;
use warnings;

UR::Object::Type->add_observer(
    aspect => 'load',
    callback => sub {
        my $meta = shift;
        my $class_name = $meta->class_name;
        if ($class_name eq 'Genome::ModelGroup') {
            require Genome::Site::TGI::Observers::ModelGroup;
        } elsif ($class_name eq 'Genome::Project') {
            require Genome::Site::TGI::Observers::Project;
        } elsif ($class_name eq 'Command::V1') {
            require Genome::Site::TGI::Observers::Command;
        } elsif ($class_name eq 'Genome::DataSource::GMSchema') {
            require Genome::Site::TGI::Observers::GMSchema;
        }
        die $@ if $@;
    },
);

1;

