#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use Test::More tests => 6;

use_ok('Genome::Model::Tools::BreakpointPal');

my $test_dir = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BreakpointPal";
ok(-e $test_dir , "test-dir exists");
chdir($test_dir);

my $pwd = `pwd`;
chomp $pwd;
ok($pwd eq $test_dir , "working in the test-dir");
system qq(rm chr11:36287905-36288124*);

system qq(gt breakpoint-pal --breakpoint-id chr11:36287905-36288124 --span);

my $fasta1 = "$test_dir/chr11:36287905-36288124.BP1-2.fasta";
my $fasta2 = "$test_dir/chr11:36287905-36288124.BP1.300.fasta";
my $fasta3 = "$test_dir/chr11:36287905-36288124.BP2.300.fasta";

ok(-f $fasta1 && -f $fasta2 && -f $fasta3 , "Three fasta's for the pal were produced");

my $ghostview = "$test_dir/chr11:36287905-36288124.BP1-2.fasta300.pal100.ghostview";
ok(-f $ghostview, "pal produced");

my $primers = "$test_dir/chr11:36287905-36288124.span.300.primer3.blast.result";
ok(-f $primers, "primer file produced");

