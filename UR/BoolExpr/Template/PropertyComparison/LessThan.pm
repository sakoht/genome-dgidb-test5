
package UR::BoolExpr::Template::PropertyComparison::LessThan;

use strict;
use warnings;

UR::Object::Type->define(
    class_name  => __PACKAGE__, 
    is => ['UR::BoolExpr::Template::PropertyComparison'],
);

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;
    my $comparison_value = shift;    
    my $property_name = $self->property_name;    
    my $property_value = $subject->$property_name;
    no warnings;
    return ($property_value < $comparison_value || $property_value lt $comparison_value ? 1 : '');
}


1;

=pod

=head1 NAME

UR::BoolExpr::Template::PropertyComparison::LessThan - Perform a less than test

=cut

