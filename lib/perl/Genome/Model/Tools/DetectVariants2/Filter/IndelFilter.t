#!/usr/bin/env perl

use strict;
use warnings;

use above "Genome";
use File::Temp;
use Test::More tests => 11;
use Data::Dumper;
use File::Compare;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

BEGIN {
    use_ok( 'Genome::Model::Tools::DetectVariants2::Filter::IndelFilter')
};

# Override lock name because if people cancel tests locks don't get cleaned up.
*Genome::SoftwareResult::_resolve_lock_name = sub {
    return Genome::Sys->create_temp_file_path;
};


my $refbuild_id = 101947881;
my $test_data_directory = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants2-Filter-SnpFilter";

# Updated to .v2 for correcting an error with newlines
my $expected_directory = $test_data_directory . "/expected";
my $detector_directory = $test_data_directory . "/samtools-r599-";
my $tumor_bam_file  = $test_data_directory. '/flank_tumor_sorted.bam';
my $normal_bam_file  = $test_data_directory. '/flank_normal_sorted.bam';
my $test_output_base = File::Temp::tempdir('Genome-Model-Tools-DetectVariants2-Filter-IndelFilter-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my $test_output_dir = $test_output_base . '/filter';

my @expected_output_files = qw| indels.hq
                                indels.hq.bed
                                indels.hq.v1.bed
                                indels.hq.v2.bed
                                indels.lq
                                indels.lq.bed
                                indels.lq.v1.bed
                                indels.lq.v2.bed | ;


my $detector_result = Genome::Model::Tools::DetectVariants2::Result->__define__(
    output_dir => $detector_directory,
    detector_name => 'test',
    detector_params => '',
    detector_version => 'awesome',
    aligned_reads => $tumor_bam_file,
    control_aligned_reads => $normal_bam_file,
    reference_build_id => $refbuild_id,
);

my $indel_filter_high_confidence = Genome::Model::Tools::DetectVariants2::Filter::IndelFilter->create(
    previous_result_id => $detector_result->id,
    output_directory => $test_output_dir,
);

ok($indel_filter_high_confidence, "created IndelFilter object");
ok($indel_filter_high_confidence->execute(), "executed IndelFilter");

for my $output_file (@expected_output_files){
    my $expected_file = $expected_directory."/".$output_file;
    my $actual_file = $test_output_dir."/".$output_file;
    is(compare($actual_file, $expected_file), 0, "$actual_file output matched expected output");
}
