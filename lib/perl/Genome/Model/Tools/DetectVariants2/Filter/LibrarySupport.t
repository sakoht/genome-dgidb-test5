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
    use_ok( 'Genome::Model::Tools::DetectVariants2::Filter::LibrarySupport');
};


# Override lock name because if people cancel tests locks don't get cleaned up.
*Genome::SoftwareResult::_resolve_lock_name = sub {
    return Genome::Sys->create_temp_file_path;
};


my $refbuild_id = 101947881;
my $input_directory = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants2-Filter-LibrarySupport/";

# Updated to .v2 for correcting an error with newlines
my $expected_dir = $input_directory . "/expected.v2/";
my $tumor_bam_file  = $input_directory. '/tumor.tiny.bam';
my $test_output_base = File::Temp::tempdir('Genome-Model-Tools-DetectVariants2-Filter-LibrarySupport-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my $test_output_dir = $test_output_base . '/filter';

my $hq_output = "$test_output_dir/indels.hq";
my $lq_output = "$test_output_dir/indels.lq";
my $hq_output_bed = "$test_output_dir/indels.hq.bed";
my $lq_output_bed = "$test_output_dir/indels.lq.bed";

my $expected_hq_output = "$expected_dir/indels.hq.expected";
my $expected_lq_output = "$expected_dir/indels.lq.expected";
my $expected_hq_bed_output = "$expected_dir/indels.hq.expected.bed";
my $expected_lq_bed_output = "$expected_dir/indels.lq.expected.bed";

my $detector_result = Genome::Model::Tools::DetectVariants2::Result->__define__(
    output_dir => $input_directory,
    detector_name => 'test',
    detector_params => '',
    detector_version => 'awesome',
    aligned_reads => $tumor_bam_file,
    reference_build_id => $refbuild_id,
);

my $library_support_filter = Genome::Model::Tools::DetectVariants2::Filter::LibrarySupport->create(
    previous_result_id => $detector_result->id,
    output_directory => $test_output_dir,
);

ok($library_support_filter, "created LibrarySupportFilter object");
ok($library_support_filter->execute(), "executed LibrarySupportFilter");

ok(-s $hq_output ,'HQ output exists and has size');
ok(-s $lq_output,'LQ output exists and has size'); 
ok(-s $hq_output_bed ,'HQ bed output exists and has size');
ok(-s $lq_output_bed,'LQ bed output exists and has size'); 

is(compare($hq_output, $expected_hq_output), 0, 'hq output matched expected output');
is(compare($lq_output, $expected_lq_output), 0, 'lq output matched expected output');

is(compare($hq_output_bed, $expected_hq_bed_output), 0, 'hq bed output matched expected output');
is(compare($lq_output_bed, $expected_lq_bed_output), 0, 'lq bed output matched expected output');
