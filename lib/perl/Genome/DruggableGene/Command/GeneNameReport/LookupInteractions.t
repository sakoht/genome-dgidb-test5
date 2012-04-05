#!/usr/bin/perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1; #This is completely unnecessary, but lets be paranoid
};

use Test::More tests => 5;
use above 'Genome';

use_ok('Genome::DruggableGene::Command::GeneNameReport::LookupInteractions');

my $test_input_file = __FILE__ . '.d/input.tsv';
my $test_output_file = __FILE__ . '.d/output.tsv';
ok(-e $test_input_file, 'test file ' . $test_input_file . ' exists');
ok(-e $test_output_file, 'test file ' . $test_output_file . ' exists');

my $test_output_dir = File::Temp::tempdir('Genome-GeneNameReport-Command-LookupInteractions-XXXXX', '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my $output_file = join("/", $test_output_dir, 'test_output');
my $command = Genome::DruggableGene::Command::GeneNameReport::LookupInteractions->create(gene_file => $test_input_file, output_file => $output_file);
isa_ok($command, 'Genome::DruggableGene::Command::GeneNameReport::LookupInteractions', 'created a LookupInteractions command');
ok($command->execute, 'Successfully excuted lookup interactions command');

system("sort $output_file -o $output_file");
my $output = `diff $test_output_file $output_file`;
#ok(!$output, 'Command output and expected output are identical') || print "$output\n";
