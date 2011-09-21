package UR::Object::View::Default::Json;

use strict;
use warnings;
require UR;
our $VERSION = "0.34"; # UR $VERSION;

use XML::Simple;
use JSON;

class UR::Object::View::Default::Json {
    is => 'UR::Object::View::Default::Text',
    has_constant => [
        toolkit     => { value => 'json' },
    ],
    has_optional => [
        encode_options => { is => 'ARRAY', default_value => ['ascii', 'pretty', 'allow_nonref', 'canonical'], doc => 'Options to enable on the JSON object; see the documentation for the JSON Perl module' },
    ],
};

my $json;
sub _json {
    my ($self) = @_;
    return $json if defined $json;

    $json = JSON->new;
    foreach my $opt ( @{ $self->encode_options } ) {
        eval { $json = $json->$opt; };
        if ($@) {
            Carp::croak("Can't initialize JSON object for encoding.  Calling method $opt from encode_options died: $@");
        }
        if (!$json) {
            Carp::croak("Can't initialize JSON object for encoding.  Calling method $opt from encode_options returned false");
        }
    }
    return $json;
}

sub _generate_content {
    my $self = shift;


    my $obj = $self->subject();

    if (!$obj) {
        Carp::confess('This JSON view couldnt get the subject of the view. class='
                    , $self->subject_class_name
                    . ' id='
                    . $self->subject_id);
    }

##        perspective => $self->perspective(),
#    my %view_args = (
#        subject_class_name => $self->subject_class_name,
#        perspective => 'detail',
#        toolkit => 'xml'
#    );
#    my $xml_view = $obj->create_view(%view_args);
#    my $xml = $xml_view->content();
#    my $hash = XMLin($xml);

    my $hash = {};
    my @attributes;
    for my $a ($obj->attributes()) {
        push @attributes, [
            $a->nomenclature(),
            $a->attribute_label(),
            $a->attribute_value()
        ];
    }
    $hash->{'aaData'} = \@attributes;

    return $self->_json->encode($hash);
}

sub _jsobj {
    my $self = shift;

    my $subject = $self->subject();
    return '' unless $subject;

    my %jsobj = ();

    for my $aspect ($self->aspects) { 
        my $val = $self->_generate_content_for_aspect($aspect);
        $jsobj{$aspect->name} = $val if defined $val;
    }

    return \%jsobj;
}

sub _generate_content_for_aspect {
    my $self = shift;
    my $aspect = shift;

    my $subject = $self->subject;
    my $aspect_name = $aspect->name;

    my $aspect_meta = $self->subject_class_name->__meta__->property($aspect_name);
    #warn $aspect_name if ref($subject) =~ /Set/;

    my @value;
    eval {
        @value = $subject->$aspect_name;
    };
    if ($@) {
        warn $@;
        return;
    }

    # Always look for a delegate view.
    # This means we replace the value(s) with their
    # subordinate widget content.
    unless ($aspect->delegate_view) {
        $aspect->generate_delegate_view;
    }

    my $ref = [];

    if (my $delegate_view = $aspect->delegate_view) {
        foreach my $value ( @value ) {
            if (Scalar::Util::blessed($value)) {
                $delegate_view->subject($value);
            } else {
                $delegate_view->subject_id($value);
            }
            $delegate_view->_update_view_from_subject();

            if ($delegate_view->can('_jsobj')) {
                push @$ref, $delegate_view->_jsobj;
            } else {
                my $delegate_text = $delegate_view->content();
                push @$ref, $delegate_text;
            }
        }
    }
    else {
        for my $value (@value) {
            if (ref($value)) {
                push @$ref, 'ref';  #TODO(ec) make this render references
            } else {
                push @$ref, $value;
            }
        }
    }

    if ($aspect_meta && $aspect_meta->is_many) {
        return $ref;
    } else {
        return shift @$ref;
    }
}

# Do not return any aspects by default if we're embedded in another view
# The creator of the view will have to specify them manually
sub _resolve_default_aspects {
    my $self = shift;
    unless ($self->parent_view) {
        return $self->SUPER::_resolve_default_aspects;
    }
    return ('id');
}

1;
