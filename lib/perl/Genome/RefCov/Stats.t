#!/gsc/bin/perl

# TODO: May need to switch if we introduce a dependency on Bio::DB::Sam
#/gsc/bin/perl5.12.1

use strict;
use warnings;

use above 'Genome';

use Test::More;

# TODO: May need to turn this on if we introduce a dependency on Bio::DB::Sam
#if ($] < 5.012) {
#  plan skip_all => "this test is only runnable on perl 5.12+"
#}

plan tests => 20;

use_ok('Genome::RefCov::Stats');
# TODO: Load a BAM file and use the actual coverage method to get array?
my @coverage = (0,0,5,5,5,5,5,0,5,5,5,5,5,0,0);
my $expected_length = scalar(@coverage);
my $stats = Genome::RefCov::Stats->create(
    name => 'Test',
   coverage => \@coverage,
);
isa_ok($stats,'Genome::RefCov::Stats');
isa_ok(ref($stats->coverage),'ARRAY');
is($stats->ref_length,$expected_length,'ref_length is '.$expected_length);
is($stats->percent_ref_bases_covered,66.67,'percent_ref_bases_covered matches expected');
is($stats->total_ref_bases,$expected_length,'total_ref_bases matches expected');
is($stats->total_covered_bases,10,'total_covered_bases matches expected');
is($stats->missing_bases,5,'missing_bases matches expected');
is($stats->gap_number,3,'gap_number matches expected');
is($stats->ave_gap_length,1.67,'ave_gap_length matches expected');
is($stats->sdev_ave_gap_length,0.58,'sdev_ave_gap_length matches expected');
is($stats->med_gap_length,'2.00','med_gap_length matches expected');
is($stats->min_depth_filter,0,'min_depth_filter matches expected');
is($stats->min_depth_discarded_bases,0,'min_depth_discarded_bases matches expected');
is($stats->percent_min_depth_discarded,'0.00','percent_min_depth_discarded matches expected');
my $stats_ref = $stats->stats;
isa_ok(ref($stats_ref),'ARRAY');
is(scalar(@{$stats_ref}),15,'Found expected elements in stats array ref');

# TODO: Find appropriate tmp location to write test file
# TODO: Write a validation file to compare
# $stats->save_stats($tmp_file);

# TODO: redirect STDOUT and validate output
ok($stats->print_stats,'Print stats to STDOUT');

my @headers = $stats->headers;
is(scalar(@headers),15,'Found expected elements in stats headers');

my @descriptions = $stats->header_descriptions;
is(scalar(@descriptions),15,'Found expected elements in stats descriptions');

# TODO: Repeat tests with min_depth filter on and coverage values sufficient for such test
exit;
