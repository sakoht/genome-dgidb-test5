#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use File::Path;
use File::Temp;
use Test::More;
use above 'Genome';
use Genome::SoftwareResult;

my $archos = `uname -a`;
if ($archos !~ /64/) {
    plan skip_all => "Must run from a 64-bit machine";
}

use_ok('Genome::Model::Tools::DetectVariants2::Sniper');

my $refbuild_id = 101947881;
my $ref_seq_build = Genome::Model::Build::ImportedReferenceSequence->get($refbuild_id);
ok($ref_seq_build, 'human36 reference sequence build') or die;

no warnings;
# Override lock name because if people cancel tests locks don't get cleaned up.
*Genome::SoftwareResult::_resolve_lock_name = sub {
    return Genome::Sys->create_temp_file_path;
};
use warnings;

my $tumor =  "/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants-Somatic-Sniper/tumor.tiny.bam";
my $normal = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants-Somatic-Sniper/normal.tiny.bam";

my $test_base_dir = File::Temp::tempdir('SomaticSniperXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites/', CLEANUP => 1);
my $test_working_dir = "$test_base_dir/output";

my $sniper = Genome::Model::Tools::DetectVariants2::Sniper->create(aligned_reads_input=>$tumor, 
                                                                   control_aligned_reads_input=>$normal,
                                                                   reference_build_id => $refbuild_id,
                                                                   output_directory => $test_working_dir,
                                                                   version => '0.7.2',
                                                                   params => '-q 1 -Q 15',
                                                                   aligned_reads_sample => 'TEST',);
ok($sniper, 'sniper command created');
$sniper->dump_status_messages(1);
my $rv = $sniper->execute;
is($rv, 1, 'Testing for successful execution.  Expecting 1.  Got: '.$rv);

my $output_snv_file = $sniper->output_directory . "/snvs.hq.bed";
my $output_indel_file = $sniper->output_directory . "/indels.hq.bed";

ok(-s $output_snv_file,'Testing success: Expecting a snv output file exists');
ok(-s $output_indel_file,'Testing success: Expecting a indel output file exists');

#I don't know what this output should like like, but we will check to see if this runs...
my $v1_test_working_dir = "$test_base_dir/output_v1";
my $sniper_v1 = Genome::Model::Tools::DetectVariants2::Sniper->create(aligned_reads_input=>$tumor, 
                                                                      control_aligned_reads_input=>$normal,
                                                                      reference_build_id => $refbuild_id,
                                                                      output_directory => $v1_test_working_dir,
                                                                      version => '1.0.0',
                                                                      params => '-q 1 -Q 15',
                                                                      aligned_reads_sample => 'TEST',);
ok($sniper_v1, 'sniper 1.0.0 command created');
$sniper_v1->dump_status_messages(1);
my $rv1= $sniper_v1->execute;
is($rv1, 1, 'Testing for successful execution.  Expecting 1.  Got: '.$rv1);

done_testing();
exit;
