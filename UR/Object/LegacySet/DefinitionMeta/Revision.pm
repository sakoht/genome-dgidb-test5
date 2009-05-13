
=head1 NAME

UR::Object::LegacySet::DefinitionMeta::Revision - A revision number hang-off 

=head1 SYNOPSIS
 
    @rev = UR::Object::LegacySet::DefinitionMeta::Revision->get(
        reference_set_id => $some_multiversion_set_id
    );
    for my $r (@rev) {
        print "Set " . $r->id 
            . " is revision " . $r->revision_num
            . " of set $some_multiversion_set_id\n";
    }


=head1 DESCRIPTION

When a set of type "revisioned" has revisions, each revision is also a set of
undetermined type.  These sets will also have an object of this type which 
associates a revision number with that particular snapshot.

=cut


package UR::Object::LegacySet::DefinitionMeta::Revision;

use warnings;
use strict;
our $VERSION = '0.1';

UR::Object::Type->define(
    class_name => 'UR::Object::LegacySet::DefinitionMeta::Revision',
    id_properties => ['revision_set_id'],
    properties => [
        revision_set_id                  => { type => '', len => undef },
        reference_set_id                 => { type => '', len => undef },
        revision_num                     => { type => '', len => undef },
    ],
);

1;

