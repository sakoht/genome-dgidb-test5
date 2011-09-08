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
    ],
    has_many_optional => [
        parts => {
            is => 'Genome::ProjectPart',
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
        user_ids => {
            calculate_from => ['parts'],
            calculate => sub {
                my (@parts) = @_;
                return map {$_->entity_id} 
                        grep { $_->entity_class_name eq 'Genome::Sys::User'} 
                        @parts;
            }
            doc => 'The user ids of people associated with this project',
        }
    ],
    table_name => 'GENOME_PROJECT',
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
    doc => 'A project, can contain any number of objects (of any type)!',
};


sub create {

    my ($class, %p) = @_;

    my $self = $class->SUPER::create(%p);

    my $user_email = Genome::Config->user_email();
    my $user = Genome::Sys::User->get( email => $user_email);

    die "Didnt create project because couldnt find user with user_email '$user_email' " if !$user;

    my $part = Genome::ProjectPart->create(
        entity_class_name => 'Genome::Sys::User',
        entity_id => $user->email(),
        project_id => $self->id
    ) || die "Not creating a project because couldnt create a part for creator/user";

    return $self;
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

