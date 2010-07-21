#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use Test::More;
require File::Compare;

my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Assembly-Stats/MsiNewbler_v2';
ok(-d $data_dir, "Data dir exists");

my $temp_dir = Genome::Utility::FileSystem->create_temp_directory();
ok(-d $temp_dir, "Temp test dir exists");

my $edit_dir = $temp_dir.'/edit_dir';
mkdir $edit_dir;
ok(-d $edit_dir, "Temp edit_dir made");

my @files = qw/ msi.contigs.bases msi.contigs.quals msi.reads.placed msi.readinfo.txt 
                newbler.ace GABJJ9O01.fasta.qual.gz GABJJ9O01.fasta.gz /;

foreach (@files) {
    symlink($data_dir."/edit_dir/$_", $temp_dir."/edit_dir/$_");
    ok(-s $temp_dir."/edit_dir/$_", "Linked $_ in temp dir");
}

ok(system("gmt assembly stats msi-newbler --assembly-directory $temp_dir --no-print-to-screen") == 0, "Command ran successfully");

my $temp_stats = $temp_dir.'/edit_dir/stats.txt';
my $data_stats = $data_dir.'/edit_dir/stats.txt';

ok(-s $temp_stats, "Tmp dir stats file made");
ok(-s $data_stats, "Data dir stats file exists");

my @diffs = `sdiff -s $temp_stats $data_stats`;
is (scalar @diffs, 0, "Stats files match") or diag(@diffs);

done_testing();

exit;
