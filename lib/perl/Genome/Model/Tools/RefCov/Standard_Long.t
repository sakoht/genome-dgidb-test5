#!/usr/bin/env perl5.12.1

use strict;
use warnings;

use Test::More;
use File::Compare;

use above 'Genome';

if ($] < 5.012) {
  plan skip_all => "this test is only runnable on perl 5.12+"
}
plan tests => 4;

use_ok('Genome::Model::Tools::RefCov::Standard');

my $tmp_dir = File::Temp::tempdir('BioSamtools-RefCov-'.Genome::Sys->username.'-XXXX',DIR => '/gsc/var/cache/testsuite/running_testsuites',CLEANUP => 1);

my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-RefCov-Standard';
my $expected_data_dir = $data_dir;

my $alignment_file_path = $data_dir .'/chr16.bam';
my $regions_file = $data_dir .'/long_test_10k.bed';

my $expected_stats_file = $expected_data_dir .'/PDL_long_test_STATS_v2.tsv';

my $ref_cov = Genome::Model::Tools::RefCov::Standard->create(
    output_directory => $tmp_dir,
    alignment_file_path => $alignment_file_path,
    roi_file_path => $regions_file,
);
isa_ok($ref_cov,'Genome::Model::Tools::RefCov::Standard');
ok($ref_cov->execute,'execute Standard command '. $ref_cov->command_name);

ok(!compare($expected_stats_file,$ref_cov->stats_file),'expected stats file '. $expected_stats_file .' is identical to '. $ref_cov->stats_file);

exit;
