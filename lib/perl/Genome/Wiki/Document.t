#!/usr/bin/env perl


use above "Genome";
use Data::Dumper;

use Test::More tests => 5;

use_ok('Genome::Wiki::Document');

my $doc = Genome::Wiki::Document->get(title => 'Main Page');
ok($doc, 'get main page');

diag('crude test of parsing');
ok($doc->user(), 'user');
ok($doc->timestamp(), 'timestamp');
ok($doc->content(), 'content');



