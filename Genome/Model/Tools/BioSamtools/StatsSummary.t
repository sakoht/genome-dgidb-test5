#!/gsc/bin/perl

use strict;
use warnings;

use Test::More tests => 5;
use File::Compare;

use above 'Genome';

use_ok('Genome::Model::Tools::BioSamtools');
use_ok('Genome::Model::Tools::BioSamtools::StatsSummary');

my $tmp_dir = File::Temp::tempdir('BioSamtools-StatsSummary-'.$ENV{USER}.'-XXXX',DIR => '/gsc/var/cache/testsuite/running_testsuites',CLEANUP => 1);
my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-BioSamtools/StatsSummary';

my $stats_file = $data_dir .'/test.stats';
my $expected_file = $data_dir .'/test_stats_summary.tsv';

my $as = Genome::Model::Tools::BioSamtools::StatsSummary->create(
    stats_file => $stats_file,
    output_file => $tmp_dir .'/test_stats_summary.tsv',
);
isa_ok($as,'Genome::Model::Tools::BioSamtools::StatsSummary');
ok($as->execute,'execute StatsSummary command '. $as->command_name);
ok(!(compare($expected_file,$as->output_file)),'expected file '. $expected_file .' matched the output file '. $as->output_file);

exit;
