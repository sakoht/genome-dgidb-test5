#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';
use Test::More;

use_ok('Genome::Model::Tools::ViromeEvent::RepeatMasker::RemoveFile');

my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-ViromeScreening/Titanium17/Titanium17_undecodable';
ok( -d $data_dir, "Test suite data dir exits" );

my $c = Genome::Model::Tools::ViromeEvent::RepeatMasker::RemoveFile->create(
    dir => $data_dir,
    );
ok($c, "Created repeat maser remove file event");

done_testing();

exit;
