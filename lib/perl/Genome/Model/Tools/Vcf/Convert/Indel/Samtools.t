#!/usr/bin/env perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

use_ok('Genome::Model::Tools::Vcf::Convert::Indel::Samtools');

my $test_dir = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-Vcf-Convert-Indel-Samtools";

my $expected_base = "expected.v2";
my $input_base = "test_input.v2";
my $expected_dir = "$test_dir/$expected_base";
my $input_dir = "$test_dir/$input_base";
my $expected_file = "$expected_dir/output.vcf";

my $output_file = Genome::Sys->create_temp_file_path;
my $input_file = "$input_dir/indels.hq";

my $command = Genome::Model::Tools::Vcf::Convert::Indel::Samtools->create( input_file => $input_file,
                                                                           output_file => $output_file,
                                                                           aligned_reads_sample => "TUMOR_SAMPLE_123",
                                                                           control_aligned_reads_sample => "CONTROL_SAMPLE_123",
                                                                           reference_sequence_build_id => 101947881);
ok($command, 'Command created');
my $rv = $command->execute;
ok($rv, 'Command completed successfully');
ok(-s $output_file, "output file created");

#The files will have a timestamp that will differ. Ignore this but check the rest.
my $expected = `cat $expected_file | grep -v fileDate`;
my $output = `cat $output_file | grep -v fileDate`;
my $diff = Genome::Sys->diff_text_vs_text($output, $expected);
ok(!$diff, 'output matched expected result')
    or diag("diff results:\n" . $diff);
done_testing();
