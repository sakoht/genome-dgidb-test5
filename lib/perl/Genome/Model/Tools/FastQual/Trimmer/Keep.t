#!/usr/bin/env perl

use strict;
use warnings;

use above "Genome";

require File::Compare;
use Test::More;

# Use
use_ok('Genome::Model::Tools::FastQual::Trimmer::Keep') or die;

# Create failures
ok(scalar(Genome::Model::Tools::FastQual::Trimmer::Keep->create->__errors__), 'Create w/o lengths');
ok(scalar(Genome::Model::Tools::FastQual::Trimmer::Keep->create(length => 'all')->__errors__), 'Create w/ length => all');
ok(scalar(Genome::Model::Tools::FastQual::Trimmer::Keep->create(length => 0)->__errors__), 'Create w/ length => 0');

# Files
my $dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-FastQual';
my $in_fastq = $dir.'/trimmer.in.fastq';
ok(-s $in_fastq, 'in fastq');
my $example_fastq = $dir.'/trimmer_keep.example.fastq';
ok(-s $example_fastq, 'example fastq');

my $tmp_dir = File::Temp::tempdir(CLEANUP => 1);
my $out_fastq = $tmp_dir.'/out.fastq';

# Ok
my $trimmer = Genome::Model::Tools::FastQual::Trimmer::Keep->create(
    input  => [ $in_fastq ],
    output => [ $out_fastq ],
    length => 50,
);
ok($trimmer, 'create trimmer');
ok($trimmer->execute, 'execute trimmer');
is(File::Compare::compare($example_fastq, $out_fastq), 0, "fastq trimmed as expected");

#print $tmp_dir; <STDIN>;
done_testing();
exit;

