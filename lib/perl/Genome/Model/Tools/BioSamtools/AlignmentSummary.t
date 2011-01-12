#!/gsc/bin/perl5.12.1

use strict;
use warnings;

use Test::More;
use File::Compare;

use above 'Genome';

if ($] < 5.012) {
  plan skip_all => "this test is only runnable on perl 5.12+"
}
plan tests => 5;

use File::Compare;
use above 'Genome';

use_ok('Genome::Model::Tools::BioSamtools');
use_ok('Genome::Model::Tools::BioSamtools::AlignmentSummary');


my $tmp_dir = File::Temp::tempdir('BioSamtools-AlignmentSummary-'.$ENV{USER}.'-XXXX',DIR => '/gsc/var/cache/testsuite/running_testsuites',CLEANUP => 1);

my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-BioSamtools/AlignmentSummary';

my $bam_file = $data_dir .'/test.bam';
my $regions_file = $data_dir .'/test_regions_zero_based_start.bed';
my $expected_output_file = $data_dir .'/alignment_summary_4.tsv';

my $as = Genome::Model::Tools::BioSamtools::AlignmentSummary->create(
    output_file => $tmp_dir .'/alignment_summary.tsv',
    bam_file => $bam_file,
    bed_file => $regions_file,
    wingspan => 0,
);
isa_ok($as,'Genome::Model::Tools::BioSamtools::AlignmentSummary');
ok($as->execute,'execute AlignmentSummary command '. $as->command_name);

ok(!compare($expected_output_file,$as->output_file),'expected output file '. $expected_output_file .' is identical to '. $as->output_file);


exit;
