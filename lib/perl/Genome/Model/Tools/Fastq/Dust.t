#!/usr/bin/perl

use strict;
use warnings;
use above "Genome";  # forces a 'use lib' when run directly from the cmdline
use Test::More tests => 3;
use File::Temp;

my $datadir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Fastq-Dust';
 
my $input = "$datadir/input.fastq";
die "no $input" unless -e $input;
my $expected_output = "$datadir/dusted.fastq";

my $temp_dir = Genome::Utility::FileSystem->create_temp_directory;
my $output = "$temp_dir/dusted.fastq";

my $cmd = Genome::Model::Tools::Fastq::Dust->create(
    fastq_file => $input,
    output_file => $output,
);
                                               

ok($cmd, "successfully created dust fastq command");
ok($cmd->execute, "successfully executed dust fastq command");
is(Genome::Utility::FileSystem->md5sum($output),
   Genome::Utility::FileSystem->md5sum($expected_output),
   'output matches what was expected');
