#!/gsc/bin/perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';
use Genome::SoftwareResult;
use Test::More;
use File::Compare;

my $archos = `uname -a`;
if ($archos !~ /64/) {
    plan skip_all => "Must run from 64-bit machine";
} else {
    plan tests => 20;
}

use_ok('Genome::Model::Tools::DetectVariants2::VarscanSomatic');

# Override lock name because if people cancel tests locks don't get cleaned up.
*Genome::SoftwareResult::_resolve_lock_name = sub {
    return Genome::Sys->create_temp_file_path;
};


my $test_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants2-VarscanSomatic/';
my $test_base_dir = File::Temp::tempdir('DetectVariants2-VarscanSomaticXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites/', CLEANUP => 1);
my $test_working_dir = "$test_base_dir/output";

my $bam_input = $test_dir . '/alignments/102922275_merged_rmdup.bam';
my $normal_bam = $test_dir . '/alignments/102922275_merged_rmdup.bam';

# Updated to .v5 due to additional column in Varscan
# Updated to .v6 due to the addition of quality and natural sort order to bed file output 
# Updated to .v7 due to the addition of read depth
# Updated to .v8 due to directory structure changes
# Updated to .v9 due to DetVar2 module
my $expected_dir = $test_dir . '/expected.v10/';
ok(-d $expected_dir, "expected results directory exists");

my $refbuild_id = 101947881;

my $version = ''; #Currently only one version of varscan

my $command = Genome::Model::Tools::DetectVariants2::VarscanSomatic->create(
    reference_build_id => $refbuild_id,
    aligned_reads_input => $bam_input,
    control_aligned_reads_input => $normal_bam,
    version => $version,
    params => "",
    output_directory => $test_working_dir,
);
ok($command, 'Created `gmt detect-variants varscan-somtic` command');
ok($command->execute, 'Executed `gmt detect-variants varscan-somatic` command');

my @file_names = qw|    indels.hq
                        indels.hq.bed
                        indels.hq.v1.bed
                        indels.hq.v2.bed
                        snvs.hq
                        snvs.hq.bed
                        snvs.hq.v1.bed
                        snvs.hq.v2.bed      |;

for my $file_name (@file_names){
    my $file = $expected_dir."/".$file_name;
    ok( -s $file, "$file_name exists and has size");
}

for my $file_name (@file_names){
    my $output_file = $test_working_dir."/".$file_name;
    my $expected_file = $expected_dir."/".$file_name;
    is(compare($output_file, $expected_file), 0, "$output_file output matched expected output");
}
