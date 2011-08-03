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
    }
};


use_ok( 'Genome::Model::Tools::DetectVariants2::BamToCna');

# Caching refseq in /var/cache/tgi-san. We gotta link these files to a tmp dir for tests so they don't get copied
my $refbuild_id = 101947881;
my $ref_seq_build = Genome::Model::Build::ImportedReferenceSequence->get($refbuild_id);
ok($ref_seq_build, 'human36 reference sequence build') or die;
my $refseq_tmp_dir = File::Temp::tempdir(CLEANUP => 1);
no warnings;
*Genome::Model::Build::ReferenceSequence::local_cache_basedir = sub { return $refseq_tmp_dir; };
*Genome::Model::Build::ReferenceSequence::copy_file = sub { 
    my ($build, $file, $dest) = @_;
    symlink($file, $dest);
    is(-s $file, -s $dest, 'linked '.$dest) or die;
    return 1; 
};
# Override lock name because if people cancel tests locks don't get cleaned up.
*Genome::SoftwareResult::_resolve_lock_name = sub {
    return Genome::Sys->create_temp_file_path;
};
use warnings;

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
$bam_to_cna_1->dump_status_messages(1);
like($bam_to_cna_1->reference_sequence_input, qr|^$refseq_tmp_dir|, "reference sequence path is in /tmp");
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

done_testing();
exit;
