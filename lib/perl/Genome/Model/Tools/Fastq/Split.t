#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
require File::Temp;
require File::Compare;
require File::Basename;

BEGIN {
    use_ok('above', 'Genome');
    use_ok('Genome::Model::Tools::Fastq::Split');
}

my $dir      = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Fastq/Split';
my $run_dir  = '/gsc/var/cache/testsuite/running_testsuites';
my $temp_dir = File::Temp::tempdir(
    "FastqSplit_XXXXXX",
    DIR     => $run_dir,
    CLEANUP => 1,
);

my $fastq_file = join('/', $dir, 'test.fq');

my $split = Genome::Model::Tools::Fastq::Split->create(
    fastq_file => $fastq_file,
    split_size => 50,
    output_directory  => $temp_dir,
);
ok($split->execute, "fastq_split runs ok");

for my $split_file ($split->split_files) {
    my $name = File::Basename::basename($split_file);
    my $ori_file = join('/', $dir, 'ori_split_dir', $name);
    is(File::Compare::compare($split_file, $ori_file), 0, "split file ($name) matches original");
}

done_testing();
