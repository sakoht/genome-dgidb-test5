#!/usr/bin/env perl
use strict;
use warnings;
use above "Genome";
use Test::More tests => 15;

class Genome::Foo { is => 'Genome::Notable' };
ok(Genome::Foo->isa('Genome::Notable'), 'made a "Genome::Notable" test class Genome::Foo');

my $o1 = Genome::Foo->create(100);
ok($o1, "created a test notable object");

my @n = $o1->notes;
is(scalar(@n),0,"no notes at start");

my $n1 = $o1->add_note(
    header_text => "head1",
    body_text => "body1",
);
ok($n1, "added a note");

is($n1->header_text, 'head1', 'header is okay');
is($n1->body_text, 'body1', 'body is okay');


my $n2 = $o1->add_note(
    header_text => 'head2',
    body_text => 'body2',
);
ok($n2, "added a 2nd note");

my $o2 = Genome::Foo->create(200);
ok($o2, "made a 2nd notable object");

my $n3 = $o2->add_note(
    header_text => 'head3',
    body_text => 'body3',
);
ok($n3, "added a note to the 2nd object");

my @o1notes = $o1->notes;
is(scalar(@o1notes),2,"got expected note count for object 1");

my @o2notes = $o2->notes;
is(scalar(@o2notes),1,"got expected note count for object 2");

print Data::Dumper::Dumper(\@o1notes,\@o2notes);

my $a1 = $o1->notes(header_text => 'head2');
ok($a1,"got expected note");
if ($a1) {
    is($a1->body_text,'body2', 'got correct header');
}

ok($o1->remove_note($n2), "removed the 2nd note from object 1");
@o1notes = $o1->notes;
is(scalar(@o1notes),1,"got expected note count for object 1");

UR::Context->_sync_databases() or die;

1;

