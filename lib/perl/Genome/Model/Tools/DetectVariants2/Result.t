#!/gsc/bin/perl

use strict;
use warnings;

BEGIN{
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above "Genome";
use Test::More tests => 25;

use_ok('Genome::Model::Tools::DetectVariants2::Result');

# Override lock name because if people cancel tests locks don't get cleaned up.
*Genome::SoftwareResult::_resolve_lock_name = sub {
    return Genome::Sys->create_temp_file_path;
};

#TODO this could really use its own very tiny dataset--we don't care about the results in this test so much as the process
my $test_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants2-Samtools/';
my $test_working_dir = File::Temp::tempdir('DetectVariants2-ResultXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites/', CLEANUP => 1);
my $bam_input = $test_dir . '/alignments/102922275_merged_rmdup.bam';

my $expected_dir = $test_dir . '/expected.v4/';
ok(-d $expected_dir, "expected results directory exists");

my $refbuild_id = 101947881;

my $version = 'r613';

my $detector_parameters = '';

my %command_params = (
    reference_build_id => $refbuild_id,
    aligned_reads_input => $bam_input,
    version => $version,
    params => $detector_parameters,
    detect_snvs => 1,
    detect_indels => 1,
    output_directory => $test_working_dir . '/test',
);

my $command = Genome::Model::Tools::DetectVariants2::Samtools->create(%command_params);

isa_ok($command, 'Genome::Model::Tools::DetectVariants2::Samtools', 'created samtools detector');
$command->dump_status_messages(1);
ok($command->execute, 'executed samtools command');
my $result = $command->_result;
isa_ok($result, 'Genome::Model::Tools::DetectVariants2::Result', 'generated result');

my $output_dir = $command->output_directory;
is(readlink($output_dir), $result->output_dir, 'created symlink to result');

$command_params{output_directory} = $test_working_dir . '/test2';
my $command2 = Genome::Model::Tools::DetectVariants2::Samtools->create(%command_params);

isa_ok($command2, 'Genome::Model::Tools::DetectVariants2::Samtools', 'created second samtools detector');
$command2->dump_status_messages(1);
ok($command2->execute, 'executed second samtools command');
my $result2 = $command->_result;
is($result2, $result, 'got back same result');

my $output_dir2 = $command2->output_directory;
is(readlink($output_dir2), $result->output_dir, 'created second symlink to result');

$command_params{output_directory} = $test_working_dir . '/test3';
$command_params{version} = 'r599';

my $command3 = Genome::Model::Tools::DetectVariants2::Samtools->create(%command_params);
isa_ok($command3, 'Genome::Model::Tools::DetectVariants2::Samtools', 'created third samtools detector');
$command3->dump_status_messages(1);
ok($command3->execute, 'executed third samtools command');
my $result3 = $command3->_result;
isa_ok($result3, 'Genome::Model::Tools::DetectVariants2::Result', 'generated third result');
isnt($result3, $result, 'produced a different result with different parameter');

my $output_dir3 = $command3->output_directory;
is(readlink($output_dir3), $result3->output_dir, 'created symlink to third result');

$ENV{GENOME_SOFTWARE_RESULT_TEST_NAME} = 'dv2-result-test';
$command_params{output_directory} = $test_working_dir . '/test4';

my $command4 = Genome::Model::Tools::DetectVariants2::Samtools->create(%command_params);
isa_ok($command4, 'Genome::Model::Tools::DetectVariants2::Samtools', 'created fourth samtools detector');
$command4->dump_status_messages(1);
ok($command4->execute, 'executed fourth samtools command');
my $result4 = $command4->_result;
isa_ok($result4, 'Genome::Model::Tools::DetectVariants2::Result', 'generated fourth result');
isnt($result4, $result3, 'produced a different result when using test name');

my $output_dir4 = $command4->output_directory;
is(readlink($output_dir4), $result4->output_dir, 'created symlink to fourth result');

$command_params{output_directory} = $test_working_dir . '/test5';

my $command5 = Genome::Model::Tools::DetectVariants2::Samtools->create(%command_params);
isa_ok($command5, 'Genome::Model::Tools::DetectVariants2::Samtools', 'created fifth samtools detector');
$command5->dump_status_messages(1);
ok($command5->execute, 'executed fifth samtools command');
my $result5 = $command5->_result;
isa_ok($result5, 'Genome::Model::Tools::DetectVariants2::Result', 'generated fifth result');
is($result5, $result4, 'the same result when using the same test name');

my $output_dir5 = $command5->output_directory;
is(readlink($output_dir5), $result4->output_dir, 'created second symlink to fourth result');
