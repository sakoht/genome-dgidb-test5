package Genome::Project;

use strict;
use warnings;
use Genome;
use Class::ISA;

class Genome::Project {
    is => 'Genome::Notable',
    id_generator => '-uuid',
    id_by => [
        id => { is => 'Text', }
    ],
    has => [
        name => {
            is => 'Text',
            doc => 'Name of the project',
        },
        creator => {
            is => 'Genome::Sys::User',
            via => 'parts',
            to => 'entity',
            where => [ 'entity_class_name' => 'Genome::Sys::User', role => 'creator', ],
            is_mutable => 1,
            is_many => 0,
        },
        user_ids => {
            is => 'Genome::Sys::User',
            via => 'parts',
            to => 'entity_id',
            where => [ 'entity_class_name' => 'Genome::Sys::User' ],
            is_mutable => 0,
            is_many => 1,
        },
    ],
    has_many_optional => [
        parts => {
            is => 'Genome::ProjectPart',
            is_mutable => 1,
            reverse_as => 'project',
            doc => 'All the parts that compose this project',
        },
        part_set => {
            is => 'Genome::ProjectPart::Set',
            is_calculated => 1,
        },
        parts_count => { 
            is => 'Number', 
            via => 'part_set', 
            to => 'count',
            doc => 'The number of parts associated with this project',
        },
        entities => {
            via => 'parts',
            to => 'entity',
            doc => 'All the objects to which the parts point',
        },
        models => {
            is => 'Genome::Model',
            via => 'parts',
            to => 'entity',
            where => [ 'entity_class_name like' => 'Genome::Model' ],
            is_mutable => 1,
            is_many => 1,
        },
        model_group => {
            is => 'Genome::ModelGroup',
            reverse_as => 'project',
        },
    ],
    table_name => 'GENOME_PROJECT',
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
    doc => 'A project, can contain any number of objects (of any type)!',
};

sub create {
    my $class = shift;
    my $self = eval { $class->SUPER::create(@_) };
    if ($@ or not $self) {
        $class->status_message("Could not create new object of type $class!" .
            ($@ ? " Reason: $@" : ""));
    }
    return $self;
}

sub rename {
    my ($self, $new_name) = @_;

    unless ($new_name) {
        $self->error_message('No new name given to rename model group');
        return;
    }

    my @projects = Genome::Project->get(name => $new_name);
    if (@projects) {
        $self->error_message("Failed to rename project (" . $self->id .
            ") from '" . $self->name . "' to '$new_name' because one already exists.");
        return;
    }

    my $old_name = $self->name;
    $self->name($new_name);
    my $rv = eval { $self->name($new_name) };
    if ($@ or not $rv) {
        $self->error_message("Could not rename project " . $self->__display_name__ .
            " from $old_name to $new_name!" .
            ($@ ? " Reason: $@" : ""));
        return;
    }

    $self->status_message("Renamed project from '$old_name' to '$new_name'");

    return 1;
}

sub get_parts_of_class {
    my $self = shift;
    my $desired_class = shift;
    croak $self->error_message('missing desired_class argument') unless $desired_class;

    my @parts = $self->parts;
    return unless @parts;

    my @desired_parts;
    for my $part (@parts) {
        my @classes = Class::ISA::self_and_super_path($part->entity->class);
        push @desired_parts, $part if grep { $_ eq $desired_class } @classes;
    }

    return @desired_parts;
}

sub delete {

    my ($self) = @_;

    for my $part ($self->parts) {
        $part->delete();
    }    

    return $self->SUPER::delete();
}


1;

