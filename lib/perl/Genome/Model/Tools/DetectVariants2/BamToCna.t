#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above "Genome";
use Test::More;
use File::Compare;
use Genome::SoftwareResult;

BEGIN {
    my $archos = `uname -a`;
    if ($archos !~ /64/) {
        plan skip_all => "Must run from 64-bit machine";
    } else {
        plan tests => 23;
    }
};


use_ok( 'Genome::Model::Tools::DetectVariants2::BamToCna');

# Override lock name because if people cancel tests locks don't get cleaned up.
*Genome::SoftwareResult::_resolve_lock_name = sub {
    return Genome::Sys->create_temp_file_path;
};

my $test_input_dir  = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants2-BamToCna/'; #Switched to whole genome normalization right around rev 61005

my $tumor_bam_file  = $test_input_dir . 'tumor.sparse.bam';
my $normal_bam_file = $test_input_dir . 'normal.sparse.bam';

my $expected_output_file_1 = $test_input_dir . 'cna.1.expected';
my $expected_output_file_2 = $test_input_dir . 'cna.2.expected';
my $expected_output_file_3 = $test_input_dir . 'cna.3.expected';
my $expected_output_file_4 = $test_input_dir . 'cna.4.expected';

my $test_output_dir = File::Temp::tempdir('Genome-Model-Tools-DetectVariants2-BamToCna-XXXXX', '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);

my $output_directory_1     = $test_output_dir . '/cna.1.out';
my $output_directory_2     = $test_output_dir . '/cna.2.out';
my $output_directory_3     = $test_output_dir . '/cna.3.out';  
my $output_directory_4     = $test_output_dir . '/cna.4.out';
my $output_file_1 = "$output_directory_1/cnvs.hq";
my $output_file_2 = "$output_directory_2/cnvs.hq";
my $output_file_3 = "$output_directory_3/cnvs.hq";
my $output_file_4 = "$output_directory_4/cnvs.hq";

my $ref_seq_build = Genome::Model::Build::ImportedReferenceSequence->get(type_name => 'imported reference sequence', name => 'NCBI-human-build36');
ok($ref_seq_build, 'Got a reference sequence build') or die('Test cannot continue without a reference sequence build');
is($ref_seq_build->name, 'NCBI-human-build36', 'Got expected reference for test case');

my $refbuild_id = 101947881;

#This window size and ratio are atypical, but allow the test to generate all data given a sparse BAM file.
my $bam_to_cna_1 = Genome::Model::Tools::DetectVariants2::BamToCna->create(
    aligned_reads_input  => $tumor_bam_file,
    control_aligned_reads_input => $normal_bam_file,
    reference_build_id => $refbuild_id,
    output_directory     => $output_directory_1,
    window_size     => 10000000,
    ratio           => 4.0,
    normalize_by_genome => 0,
);

ok($bam_to_cna_1, 'created BamToCna object with ratio of 4.0');
ok($bam_to_cna_1->execute(), 'executed BamToCna object with ratio of 4.0');

ok(-s $output_file_1, 'generated output for ratio of 4.0');
is(compare($output_file_1, $expected_output_file_1), 0, 'output for ratio of 4.0 matched expected results');

ok(-s $output_file_1 . ".png", 'generated copy number graphs for ratio of 4.0');

#A more normal ratio should result in missing some chromosomes in the output.
my $bam_to_cna_2 = Genome::Model::Tools::DetectVariants2::BamToCna->create(
    aligned_reads_input  => $tumor_bam_file,
    control_aligned_reads_input => $normal_bam_file,
    reference_build_id => $refbuild_id,
    output_directory     => $output_directory_2,
    window_size     => 10000000,
    ratio           => 0.25,
    normalize_by_genome => 0,
);

ok($bam_to_cna_2, 'created BamToCna object with ratio of 0.25');
ok($bam_to_cna_2->execute(), 'executed BamToCna object with ratio of 0.25');

ok(-s $output_file_2, 'generated output for ratio of 0.25');
is(compare($output_file_2, $expected_output_file_2), 0, 'output for ratio of 0.25 matched expected results');

ok(-s $output_file_2 . ".png", 'generated copy number graphs for ratio of 0.25');

#This window size and ratio are atypical, but allow the test to generate all data given a sparse BAM file. This file is with whole genome normalization
my $bam_to_cna_3 = Genome::Model::Tools::DetectVariants2::BamToCna->create(
    aligned_reads_input  => $tumor_bam_file,
    control_aligned_reads_input => $normal_bam_file,
    reference_build_id => $refbuild_id,
    output_directory     => $output_directory_3,
    window_size     => 10000000,
    ratio           => 4.0
);

ok($bam_to_cna_3, 'created BamToCna object with ratio of 4.0 and whole genome normalization');
ok($bam_to_cna_3->execute(), 'executed BamToCna object with ratio of 4.0 and whole genome normalization');

ok(-s $output_file_3, 'generated output for ratio of 4.0');
is(compare($output_file_3, $expected_output_file_3), 0, 'output for ratio of 4.0 and whole genome normalization matched expected results');

ok(-s $output_file_3 . ".png", 'generated copy number graphs for ratio of 4.0 and whole genome normalization');

#A more normal ratio should result in missing some chromosomes in the output. Whole genome normalized
my $bam_to_cna_4 = Genome::Model::Tools::DetectVariants2::BamToCna->create(
    aligned_reads_input  => $tumor_bam_file,
    control_aligned_reads_input => $normal_bam_file,
    reference_build_id => $refbuild_id,
    output_directory     => $output_directory_4,
    window_size     => 10000000,
    ratio           => 0.25

);

ok($bam_to_cna_4, 'created BamToCna object with ratio of 0.25 and whole genome normalization');
ok($bam_to_cna_4->execute(), 'executed BamToCna object with ratio of 0.25 and whole genome normalization');

ok(-s $output_file_4, 'generated output for ratio of 0.25 and whole genome normalization');
is(compare($output_file_4, $expected_output_file_4), 0, 'output for ratio of 0.25 matched expected results and whole genome normalization');

ok(-s $output_file_4 . ".png", 'generated copy number graphs for ratio of 0.25 and whole genome normalization');
