#!/gsc/bin/perl

use strict;
use warnings;

use Test::More tests => 6;

use above 'Genome';

use_ok('Genome::Model::Tools::BioSamtools::CoverageStats');

my $tmp_dir = File::Temp::tempdir('BioSamtools-CoverageStats-'.$ENV{USER}.'-XXXX',DIR => '/gsc/var/cache/testsuite/running_testsuites',CLEANUP => 0);

my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-BioSamtools/RefCov';

my $bam_file = $data_dir .'/test.bam';
my $regions_file = $data_dir .'/test_regions.bed';
my @wingspans = qw/0 200/;
my @minimum_depths = qw/1 10 20/;
my $stats = Genome::Model::Tools::BioSamtools::CoverageStats->create(
    output_directory => $tmp_dir,
    bam_file => $bam_file,
    bed_file => $regions_file,
    wingspan_values => join(',',@wingspans),
    minimum_depths => join(',',@minimum_depths),
    minimum_base_quality => 20,
    minimum_mapping_quality => 1,
);
isa_ok($stats,'Genome::Model::Tools::BioSamtools::CoverageStats');
ok($stats->execute,'execute CoverageStats command '. $stats->command_name);
is(scalar($stats->alignment_summaries),scalar(@wingspans),'found the correcnt number of alignment summaries');
is(scalar($stats->stats_summaries),(scalar(@wingspans)),'found the correct number of stats summaries');
is(scalar($stats->stats_files),(scalar(@wingspans)),'found the correct number of stats files');

exit;
