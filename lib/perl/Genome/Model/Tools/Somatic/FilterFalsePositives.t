#!/gsc/bin/perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use strict;
use warnings;

use above 'Genome';

use Test::More tests => 16;

use_ok('Genome::Model::Tools::Somatic::FilterFalsePositives');

my $test_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Somatic-FilterFalsePositives';

my $bam_file = join('/', $test_data_dir, 'tumor.tiny.bam');
my $variant_file = join('/', $test_data_dir, 'varscan.snp.test');
my $varscan_variant_file = join('/', $test_data_dir, 'varscan.snp.test.vs_format');

my $expected_result_dir = join('/', $test_data_dir, '1');
my $expected_output_file = join('/', $expected_result_dir, 'varscan.snp.Somatic.strandfilter');
my $expected_filtered_file = join('/', $expected_result_dir, 'varscan.snp.Somatic.failed_strandfilter');
my $expected_readcount_file = join('/', $expected_result_dir, 'varscan.snp.Somatic.strandfilter.readcounts');

my $tmpdir = File::Temp::tempdir('Somatic-FilterFalsePositivesXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites/', CLEANUP => 1);
my $output_file = join('/', $tmpdir, 'varscan.snp.Somatic.strandfilter');
my $filtered_file = join('/', $tmpdir, 'varscan.snp.Somatic.failed_strandfilter');
my $readcount_file = $output_file . '.readcounts';

my $reference = Genome::Model::Build::ImportedReferenceSequence->get_by_name('NCBI-human-build36');
isa_ok($reference, 'Genome::Model::Build::ImportedReferenceSequence', 'loaded reference sequence');

my $filter_command = Genome::Model::Tools::Somatic::FilterFalsePositives->create(
    bam_file => $bam_file,
    variant_file => $variant_file,
    output_file => $output_file,
    filtered_file => $filtered_file,

    reference => $reference->fasta_file,
    min_strandedness => 0.01,
    min_var_freq => 0.05,
    min_var_count => 4,
    min_read_pos => 0.10,
    max_mm_qualsum_diff => 50,
    max_var_mm_qualsum => 0,
    max_mapqual_diff => 30,
    max_readlen_diff => 25,
    min_var_dist_3 => 0.20,
    min_homopolymer => 5,
);
$filter_command->dump_status_messages(1);
isa_ok($filter_command, 'Genome::Model::Tools::Somatic::FilterFalsePositives', 'created filter command');
ok($filter_command->execute(), 'executed filter command');

my $output_diff = Genome::Sys->diff_file_vs_file($expected_output_file, $output_file);
ok(!$output_diff, 'output file matches expected result')
    or diag("diff:\n" . $output_diff);

my $filtered_diff = Genome::Sys->diff_file_vs_file($expected_filtered_file, $filtered_file);
ok(!$filtered_diff, 'filtered file matches expected result')
    or diag("diff:\n" . $filtered_diff);

SKIP: {
    skip "There are sometimes meaningless differences in the output (nan vs. -nan).", 1;
    my $readcount_diff = Genome::Sys->diff_file_vs_file($expected_readcount_file, $readcount_file);
    ok(!$readcount_diff, 'readcount file matches expected result')
        or diag("diff:\n" . $readcount_diff);
}

my $filter_command2 = Genome::Model::Tools::Somatic::FilterFalsePositives->create(
    bam_file => $bam_file,
    variant_file => $variant_file,
    output_file => $output_file . '.2',
    filtered_file => $filtered_file . '.2',

    reference => $reference->fasta_file,
    min_strandedness => 0.01,
    min_var_freq => 0.05,
    min_var_count => 4,
    min_read_pos => 0.10,
    max_mm_qualsum_diff => 50,
    max_var_mm_qualsum => 0,
    max_mapqual_diff => 30,
    max_readlen_diff => 25,
    min_var_dist_3 => 0.20,
    min_homopolymer => 5,

    use_readcounts => $expected_readcount_file,
);
$filter_command->dump_status_messages(1);
isa_ok($filter_command2, 'Genome::Model::Tools::Somatic::FilterFalsePositives', 'created second filter command');
ok($filter_command2->execute(), 'executed second filter command');

my $output_diff2 = Genome::Sys->diff_file_vs_file($expected_output_file, $output_file. '.2');
ok(!$output_diff2, 'output file matches expected result')
    or diag("diff:\n" . $output_diff2);

my $filtered_diff2 = Genome::Sys->diff_file_vs_file($expected_filtered_file, $filtered_file . '.2');
ok(!$filtered_diff2, 'filtered file matches expected result')
    or diag("diff:\n" . $filtered_diff2);

#for this test readcount file was supplied, so nothing to compare to.

my $filter_command3 = Genome::Model::Tools::Somatic::FilterFalsePositives->create(
    bam_file => $bam_file,
    variant_file => $varscan_variant_file,
    output_file => $output_file . '.3',
    filtered_file => $filtered_file . '.3',

    reference => $reference->fasta_file,
    min_strandedness => 0.01,
    min_var_freq => 0.05,
    min_var_count => 4,
    min_read_pos => 0.10,
    max_mm_qualsum_diff => 50,
    max_var_mm_qualsum => 0,
    max_mapqual_diff => 30,
    max_readlen_diff => 25,
    min_var_dist_3 => 0.20,
    min_homopolymer => 5,
);
$filter_command->dump_status_messages(1);
isa_ok($filter_command3, 'Genome::Model::Tools::Somatic::FilterFalsePositives', 'created second filter command');
ok($filter_command3->execute(), 'executed second filter command');

my $output_diff3 = Genome::Sys->diff_file_vs_file($expected_output_file, $output_file. '.3');
ok(!$output_diff3, 'output file matches expected result')
    or diag("diff:\n" . $output_diff3);

my $filtered_diff3 = Genome::Sys->diff_file_vs_file($expected_filtered_file, $filtered_file . '.3');
ok(!$filtered_diff3, 'filtered file matches expected result')
    or diag("diff:\n" . $filtered_diff3);

SKIP: {
    skip "There are sometimes meaningless differences in the output (nan vs. -nan).", 1;
    my $readcount_diff3 = Genome::Sys->diff_file_vs_file($expected_readcount_file, $output_file . '.3.readcounts');
    ok(!$readcount_diff3, 'readcount file matches expected result')
        or diag("diff:\n" . $readcount_diff3);
}
