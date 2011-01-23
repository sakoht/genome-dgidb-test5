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

my $test_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants-Samtools/';
my $test_working_dir = File::Temp::tempdir('DetectVariants-SamtoolsXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites/', CLEANUP => 1);

my $bam_input = $test_dir . '/alignments/102922275_merged_rmdup.bam';

# Updated to .v4 after discussion about our BED standard [insertions start the base before; indels the first removed base]
# Updated to .v5 for addition of quality data and natural sorting order
# Updated to .v6 for later and faster samtools version r613
my $expected_dir = $test_dir . '/expected.v6/';

my $ref_seq_build = Genome::Model::Build::ImportedReferenceSequence->get(type_name => 'imported reference sequence', name => 'NCBI-human-build36');
ok($ref_seq_build, 'Got a reference sequence build') or die('Test cannot continue without a reference sequence build');
is($ref_seq_build->name, 'NCBI-human-build36', 'Got expected reference for test case');

my $ref_seq_input = $ref_seq_build->full_consensus_path('fa');
ok(Genome::Sys->check_for_path_existence($ref_seq_input), 'Got a reference FASTA') or die('Test cannot continue without a reference FASTA');

my $version = 'r613';

my $snv_parameters = my $indel_parameters = '';

my $command = Genome::Model::Tools::DetectVariants::Samtools->create(
    reference_sequence_input => $ref_seq_input,
    aligned_reads_input => $bam_input,
    version => $version,
    snv_params => $snv_parameters,
    indel_params => $indel_parameters,
    detect_snvs => 1,
    detect_indels => 1,
    output_directory => $test_working_dir,
);
ok($command, 'Created `gmt detect-variants samtools` command');
ok($command->execute, 'Executed `gmt detect-variants samtools` command');

my $diff_cmd = sprintf('diff -r -q %s %s', $test_working_dir, $expected_dir);

my $diff = `$diff_cmd`;
is($diff, '', 'No differences in output from expected result from running samtools for this version and parameters');
