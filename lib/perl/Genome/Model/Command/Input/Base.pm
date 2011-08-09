package Genome::Model::Command::Input::Base;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Input::Base {
    is => 'Genome::Command::Base',
    is_abstract => 1,
    has => [
        model => { 
            is => 'Genome::Model',
            shell_args_position => 1,
            doc => 'Model to modify inputs. Resolved from command line via text string.',
        },
    ],
    doc => 'work with model inputs.',
};

sub help_brief {
    my $class = ref($_[0]) || $_[0];
    return $class->get_class_object->doc if not $class or $class eq __PACKAGE__;
    my ($func) = $class =~ /::(\w+)$/;
    return ucfirst($func).' model inputs';
}

sub help_detail {
    return help_brief(@_);
}

sub display_name_for_value {
    my ($self, $value) = @_;

    Carp::confess('No value to get display name') if not defined $value;

    if ( not ref $value ) { 
        return $value;
    }
    my $display_name = eval{ $value->__display_name__; };
    return $display_name if $display_name;
    return $value->id;
}

sub values_from_property_for_filter {
    my ($self, $property, $filter) = @_;

    Carp::confess('No property to get values for filter') if not $property;
    Carp::confess('No filter to get values from property') if not $filter;

    my $data_type = $property->{data_type};
    my $name = $property->{name};
    my @values;
    if ( $data_type->can('get') ) {
        $filter = ( $filter !~ /\=/ ) ? 'id='.$filter : $filter;
        my $bx = eval { UR::BoolExpr->resolve_for_string($data_type, $filter); };
        if ( not $bx ) {
            $self->error_message("Failed to create boolean expression for $name ($data_type) from '$filter'");
            return;
        }
        @values = $data_type->get($bx);
        if ( not @values ) {
            $self->error_message("Failed to get $name ($data_type) for $filter");
            return;
        }
    }
    else { 
        @values = ( $filter );
    }

    if ( $property->{is_many} ) {
        return @values;
    }
    elsif ( @values > 1 ) {
        $self->error_message(
            "Singular property ($name) cannot have more than one value (".join(', ', grep { defined } (@values)).')'
        );
        return;
    }
    else {
        return $values[0];
    }
}

sub unique_values_from_property_for_filter {
    my ($self, $property, @filters) = @_;

    Carp::confess('No property to get values for filter') if not $property;
    Carp::confess('No filter to get values from property') if not @filters;

    my %values;
    for my $filter ( @filters ) {
        my @values = $self->values_from_property_for_filter($property, $filter);
        return if not @values;
        for my $value ( @values ) {
            my $id = ( $value->can('id') ? $value->id : $value );
            $values{$id} = $value;
        }
    }

    return %values;
}

sub show_inputs_and_values_for_model {
    my ($self, $model) = @_;

    my $names = Genome::Model::Command::Input::Show->create(model => $model->id);
    $names->dump_status_messages(1);
    $names->execute;

    return 1;
}

1;

