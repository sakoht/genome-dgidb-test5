#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';
use Test::More;

use_ok('Genome::Model::Tools::ViromeEvent::Assignment::Generate');

my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-ViromeScreening/Titanium17/Titanium17_undecodable';
ok( -d $data_dir, "Test suite data dir exists" );

#create
my $c = Genome::Model::Tools::ViromeEvent::Assignment::Generate->create(
    dir => $data_dir,
    );
ok($c, "Created assignment generate event");

done_testing();

exit;
