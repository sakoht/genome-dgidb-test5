#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 49;

use IO::File;

use File::Basename;
use lib File::Basename::dirname(__FILE__).'/../..';
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT; # dummy namespace

# FIXME - this doesn't test the UR::DataSource::File internals like seeking and caching

my $ds = URT::DataSource::SomeFile->get();

my $filename = $ds->server;
ok($filename, 'URT::DataSource::SomeFile has a server');
unlink $filename if -f $filename;

my $rs = $ds->record_separator;

our @data = ( [ 1, 'Bob', 'blue' ],
             [ 2, 'Fred', 'green' ],
             [ 3, 'Joe', 'red' ],
             [ 4, 'Frank', 'yellow' ],
           );

&setup($ds);



my $fh = $ds->get_default_handle();
ok($fh, "got a handle");
isa_ok($fh, 'IO::Handle', 'Returned handle is the proper class');

my $thing = URT::Things->get(thing_name => 'Fred');
ok($thing, 'singular get() returned an object');
is($thing->id, 2, 'object id is correct');
is($thing->thing_id, 2, 'thing_id is correct');
is($thing->thing_name, 'Fred', 'thing_name is correct');
is($thing->thing_color, 'green', 'thing_color is correct');

my @things = URT::Things->get();
is(scalar(@things), scalar(@data), 'multiple get() returned the right number of objects');
for (my $i = 0; $i < @data; $i++) {
    # They should get returned in the same order, since @data is sorted
    is($things[$i]->thing_id, $data[$i]->[0], "Object $i thing_id is correct");
    is($things[$i]->thing_name, $data[$i]->[1], "Object $i thing_name is correct");
    is($things[$i]->thing_color, $data[$i]->[2], "Object $i thing_color is correct");
}


my $iter1 = URT::Things->create_iterator();
my $iter2 = URT::Things->create_iterator();
for (my $i = 0; $i < @data; $i++) {
    my $obj = $iter1->next();
    is($obj->thing_id, $data[$i]->[0], 'Iterator 1, thing_id is correct');
    is($obj->thing_name, $data[$i]->[1], 'Iterator 1, thing_name is correct');
    is($obj->thing_color, $data[$i]->[2], 'Iterator 1, thing_color is correct');

    $obj = $iter2->next();
    is($obj->thing_id, $data[$i]->[0], 'Iterator 2, thing_id is correct');
    is($obj->thing_name, $data[$i]->[1], 'Iterator 2, thing_name is correct');
    is($obj->thing_color, $data[$i]->[2], 'Iterator 2, thing_color is correct');
}

my $obj = $iter1->next();
ok(! defined($obj), 'Iterator 1 returns undef when all data is exhausted');
$obj = $iter2->next();
ok(! defined($obj), 'Iterator 2 returns undef when all data is exhausted');


unlink URT::DataSource::SomeFile->server;


sub setup {
    my $ds = shift;
    my $filename = $ds->server;

    my $fh = IO::File->new($filename, '>');
    ok($fh, 'opened file for writing');

    my $delimiter = $ds->delimiter;
    my $rs = $ds->record_separator;

    foreach my $line ( @data ) {
        $fh->print(join($delimiter, @$line),$rs);
    }
    $fh->close;

    my $c = UR::Object::Type->define(
        class_name => 'URT::Things',
        id_by => [
            thing_id => { is => 'Integer' },
        ],
        has => [
            thing_name => { is => 'String' },
            thing_color => { is => 'String' },
        ],
        table_name => 'FILE',
        data_source => 'URT::DataSource::SomeFile'
    );

    ok($c, 'Created class');
}


1;
