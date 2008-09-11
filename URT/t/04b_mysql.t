#!/usr/bin/env perl
use strict;
use warnings;

use Test::More skip_all => "enable after configuring MySQL";
use URT;

my $dbh = URT::DataSource::SomeMySQL->get_default_handle;
ok($dbh, "got a handle");
isa_ok($dbh, 'UR::DBI::db', 'Returned handle is the proper class');


1;
