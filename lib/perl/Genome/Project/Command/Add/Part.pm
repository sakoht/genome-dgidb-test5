package Genome::Project::Command::Add::Part;

use strict;
use warnings;

use Genome;

class Genome::Project::Command::Add::Part { 
    is => 'Command::V2',
    has => [
        projects => {
            is => 'Genome::Project',
            is_many => 1,
            shell_args_position => 1,
            doc => 'Project(s), resolved via test string.',
        },
        class_name => {
            is => 'Text',
            is_optional => 1,
            doc => 'The class name of the object to add. To add a value, leave undefined.',
        },
        value => {
            is => 'Text',
            doc => 'A string that can be any value or a value to get objects to add to projects.',
        },
        role => {
            is => 'Text',
            is_optional => 1,
            doc => 'The role of the part',
        },
        label => {
            is => 'Text',
            is_optional => 1,
            doc => 'The label for the part',
        },
    ],
};

sub sub_command_sort_position { .5 };

sub help_synopsis {
    my $class = shift;
    my $command_name = $class->command_name;
    return <<HELP;
 Add to a project (id 1) a project with id 2:
  $command_name id=1 --class-name Genome::Project --value id=2
    
 Add a priority value to project name 'High Priority':
  $command_name name='High Priority' --value 10 --label priority
HELP
}

sub execute {
    my $self = shift;

    $self->status_message('Add to projects...');

    my @objects = ( not $self->class_name or $self->class_name eq 'UR::Value' )
    ? $self->_get_ur_value_for_value($self->value)
    : $self->_get_objects_for_class_and_value($self->class_name, $self->value);
    return if not @objects;

    my %params;
    for my $property (qw/ role label /) {
        my $value = $self->$property;
        next if not defined $value;
        $params{$property} = $value;
        $self->status_message(ucfirst($property).': '.$value);
    }

    for my $project ( $self->projects ) {
        $self->status_message('Project: '.$project->__display_name__);
        for my $object ( @objects ) {
            my $existing_part = $project->part(entity => $object); # FIXME use the params, but for now cannot add an object more than once
            if ( not $existing_part ) {
                $project->add_part(entity => $object, %params);
                $self->status_message('Added: '.$object->__display_name__);
            }
            else {
                $self->status_message('Skipped, already assigned: '.$object->__display_name__);
            }
        }
    }

    $self->status_message('Done');

    return 1;
}

sub _get_objects_for_class_and_value {
    my ($self, $class, $value) = @_;

    $self->status_message('Class: '.$class);
    $self->status_message('Value: '.$class);

    my $bx = eval {
        UR::BoolExpr->resolve_for_string($class, $value);
    };
    if ( not $bx ) {
        $self->error_message($@);
        return;
    }

    my @objects = $class->get($bx);
    if ( not @objects ) {
        $self->status_message("No objects found for $class with value '$value'");
        return;
    }

    return @objects;
}

sub _get_ur_value_for_value {
    my ($self, $value) = @_;

    $self->status_message('Value: '.$value);

    if ( ref $value ) { # developer error
        $self->error_message('Cannot use a reference as value to get a UR::Value');
        return;
    }

    return UR::Value->get($value);
}

1;

