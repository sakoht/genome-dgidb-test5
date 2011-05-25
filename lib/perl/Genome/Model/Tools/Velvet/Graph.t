#!/usr/bin/env perl

use strict;
use warnings;

use above "Genome";
use Test::More tests => 6;
use File::Copy;
use File::Temp 'tempdir';
BEGIN {
    use_ok('Genome::Model::Tools::Velvet::Graph');
}

# The directory contains files that this tool needs to run (apparently), and it
# also writes to that diretory. So copy the data in /gsc/var/cache/testsuite/data to
# the temp dir created in /gsc/var/cache/testsuite/running_testsuites
my $test_dir = tempdir(
    'Genome-Model-Tools-Velvet-XXXXXX',
    DIR => '/gsc/var/cache/testsuite/running_testsuites/',
    UNLINK => 1,
    CLEANUP => 1,
);
my $dir = $test_dir.'/velvet_run';

my $file_location = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Velvet/Graph/velvet_run/';
ok(-d $file_location, "input directory found at $file_location");

my $cp_rv = system("cp -r $file_location $test_dir");
ok($cp_rv == 0, "copy from $file_location to $test_dir successful");

chmod(0775, $dir);
my $vg1 = Genome::Model::Tools::Velvet::Graph->create(
    directory  => $dir,
    cov_cutoff => 3.3,
    amos_file  => 1,
    read_trkg  => 1,
);

ok($vg1->execute, 'velvetg runs ok');

my $vg2 = Genome::Model::Tools::Velvet::Graph->create(
    cov_cutoff => 3.3,
    amos_file  => 1,
    read_trkg  => 1,
);

ok(!$vg2, 'default dir does not exist');

my $vg3 = Genome::Model::Tools::Velvet::Graph->create(
    directory  => $dir,
    cov_cutoff => 6,
    amos_file  => 1,
    read_trkg  => 1,
);

ok($vg3->execute, 'velvetg runs ok, but contigs.fa is empty');

exit;
