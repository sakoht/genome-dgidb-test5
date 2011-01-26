#!/gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

use Test::More;

my $archos = `uname -a`;
if ($archos !~ /64/) {
    plan skip_all => "Must run from 64-bit machine";
} else {
    plan tests => 6;
}

my $test_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants-VarScan/';
my $test_working_dir = File::Temp::tempdir('DetectVariants-VarScanXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites/', CLEANUP => 1);

my $bam_input = $test_dir . '/alignments/102922275_merged_rmdup.bam';

# Updated to .v5 due to additional column in VarScan
# Updated to .v6 due to the addition of quality and natural sort order to bed file output 
my $expected_dir = $test_dir . '/expected.v6/';

my $ref_seq_build = Genome::Model::Build::ImportedReferenceSequence->get(type_name => 'imported reference sequence', name => 'NCBI-human-build36');
ok($ref_seq_build, 'Got a reference sequence build') or die('Test cannot continue without a reference sequence build');
is($ref_seq_build->name, 'NCBI-human-build36', 'Got expected reference for test case');

my $ref_seq_input = $ref_seq_build->full_consensus_path('fa');
ok(Genome::Sys->check_for_path_existence($ref_seq_input), 'Got a reference FASTA') or die('Test cannot continue without a reference FASTA');

my $version = ''; #Currently only one version of var-scan
my $snv_parameters = my $indel_parameters = '';

my $command = Genome::Model::Tools::DetectVariants2::VarScan->create(
    reference_sequence_input => $ref_seq_input,
    aligned_reads_input => $bam_input,
    version => $version,
    snv_params => $snv_parameters,
    indel_params => $indel_parameters,
    detect_snvs => 1,
    detect_indels => 1,
    output_directory => $test_working_dir,
);
ok($command, 'Created `gmt detect-variants var-scan` command');
ok($command->execute, 'Executed `gmt detect-variants var-scan` command');

my $diff_cmd = sprintf('diff -r -q %s %s', $test_working_dir, $expected_dir);

my $diff = `$diff_cmd`;
is($diff, '', 'No differences in output from expected result from running var-scan for this version and parameters');
