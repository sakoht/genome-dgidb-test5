package UR::Object::Set;

use strict;
use warnings;
use UR;

class UR::Object::Set {
    is => 'UR::Value',
    is_abstract => 1,
    subclassify_by => 'member_class_name',
    type_has => [
        member_class_name   => { is => 'Text' },
    ],
    has => [
        rule                => { is => 'UR::BoolExpr', id_by => 'id' },
        member_class_name   => { via => 'rule', to => 'subject_class_name' },
    ],
    doc => 'an unordered group of distinct UR::Objects'
};

sub members {
    my $self = shift;
    my $rule = $self->rule;
    while (@_) {
        $rule = $rule->add_filter(shift, shift);
    }
    return $self->member_class_name->get($rule);
}

sub subset {
    my $self = shift;
    my $member_class_name = $self->member_class_name;
    my $bx = UR::BoolExpr->resolve_for_class_and_params($member_class_name,@_);
    my $subset = $self->class->get($bx->id);
    return $subset;
}

sub group_by {
    my $self = shift;
    my @group_by = @_;
    my $grouping_rule = $self->rule->add_filter(-group_by => \@group_by);
    my @groups = UR::Context->get_objects_for_class_and_rule( 
        $self->member_class_name, 
        $grouping_rule, 
        undef,  #$load, 
        0,      #$return_closure, 
    );
    return @groups;
}

sub count {
    $_[0]->__init unless $_[0]->{__init};
    return $_[0]->{count};
}

sub AUTOSUB {
    my ($method,$class) = @_;
    my $member_class_name = $class;
    $member_class_name =~ s/::Set$//g; 
    return unless $member_class_name; 
    my $member_class_meta = $member_class_name->get_class_object;
    my $member_property_meta = $member_class_meta->property_meta_for_name($method);
    return unless $member_property_meta;
    return sub {
        my $self = shift;
        if (@_) {
            die "set properties are not mutable!";
        }
        my $rule = $self->rule;
        if ($rule->specifies_value_for_property_name($method)) {
            return $rule->specified_value_for_property_name($method);
        } 
        else {
            my @members = $self->members;
            my @values = map { $_->$method } @members;
            return @values if wantarray;
            return if not defined wantarray;
            die "Multiple values: @values match set propety $method!" if @values > 1 and not wantarray;
            return $values[0];
        }
    }; 
}

1;

