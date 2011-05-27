#!/usr/bin/env perl

use strict;
use warnings;

use above "Genome";

use File::Temp;
use Test::More tests => 2;

BEGIN {
        use_ok('Genome::Model::Tools::WuBlast::Blastx');
}

my $test_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-WuBlast';
my $tmp_dir = File::Temp::tempdir('BLASTX-XXXXX',DIR =>'/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);

my $blast1 = Genome::Model::Tools::WuBlast::Blastx->create(
    database   => $test_dir.'/protein.fa',
    query_file => $test_dir.'/query.fa',
    output_directory => $tmp_dir,
);

ok($blast1->execute, 'Blast1 finished ok');


exit;

