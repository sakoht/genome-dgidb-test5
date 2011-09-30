#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;

use above 'Genome';

use_ok('Genome::Model::Tools::Vcf::Convert::Snv::Sniper');

my $test_dir = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-Vcf-Convert-Snv-Sniper";
# V2 updated with various corrections
# V3 - remove VT INFO field in header and VT=SNP in the body
# V4 - add source in header
# V5 - Correct the AD and BQ fields number attribute
my $expected_base = "expected.v5";
my $expected_dir = "$test_dir/$expected_base";
my $expected_file = "$expected_dir/output.vcf";

my $output_file = Genome::Sys->create_temp_file_path;
my $input_file = "$test_dir/snvs.hq";

my $command = Genome::Model::Tools::Vcf::Convert::Snv::Sniper->create( input_file => $input_file, 
                                                                       output_file  => $output_file,
                                                                       aligned_reads_sample => "TUMOR_SAMPLE_123",
                                                                       control_aligned_reads_sample => "CONTROL_SAMPLE_123",
                                                                       reference_sequence_build_id => 101947881);

ok($command, 'Command created');
my $rv = $command->execute;
ok($rv, 'Command completed successfully');
ok(-s $output_file, "output file created");

# The files will have a timestamp that will differ. Ignore this but check the rest.
my $expected = `cat $expected_file | grep -v fileDate`;
my $output = `zcat $output_file | grep -v fileDate`;
my $diff = Genome::Sys->diff_text_vs_text($output, $expected);
ok(!$diff, 'output matched expected result')
    or diag("diff results:\n" . $diff);
