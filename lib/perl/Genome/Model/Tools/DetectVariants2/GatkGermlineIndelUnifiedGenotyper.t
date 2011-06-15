#!/usr/bin/env perl

use strict;
use warnings;

use File::Path;
use File::Temp;
use File::Compare;
use Test::More;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';

my $archos = `uname -a`;
if ($archos !~ /64/) {
    plan skip_all => "Must run from a 64-bit machine";
}
else {
    plan tests => 6;
}

my $test_data = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants2-GatkGermlineIndelUnifiedGenotyper";
my $expected_data = "$test_data/expected.v2";
my $tumor =  $test_data."/flank_tumor_sorted.13.tiny.bam";

my $tmpbase = File::Temp::tempdir('GatkGermlineIndelUnifiedGenotyperXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites/', CLEANUP => 1);
my $tmpdir = "$tmpbase/output";

my $refbuild_id = 101947881;

my $gatk_somatic_indel = Genome::Model::Tools::DetectVariants2::GatkGermlineIndelUnifiedGenotyper->create(
        aligned_reads_input=>$tumor, 
        reference_build_id => $refbuild_id,
        output_directory => $tmpdir, 
        mb_of_ram => 3000,
        version => 5336,
);

ok($gatk_somatic_indel, 'gatk_germline_indel command created');
my $rv = $gatk_somatic_indel->execute;
is($rv, 1, 'Testing for successful execution.  Expecting 1.  Got: '.$rv);

my @files = qw|
                    indels.hq
                    indels.hq.bed
                    indels.hq.v1.bed
                    indels.hq.v2.bed |;

for my $file (@files){
    my $expected_file = "$expected_data/$file";
    my $actual_file = "$tmpdir/$file";
    is(compare($actual_file,$expected_file),0,"Actual file is the same as the expected file: $file")
        || system("diff -u $expected_file $actual_file");
}
