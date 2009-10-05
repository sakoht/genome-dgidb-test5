#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use Genome::Model::Tools::Sam::Merge;
use Test::More tests => 4;

my $input = "/gsc/var/cache/testsuite/data/Genome-InstrumentData-Alignment/new.bam";
my $input_bad = "/gsc/var/cache/testsuite/data/Genome-InstrumentData-Alignment/old.bam";

my $hv = Genome::Model::Tools::Sam::ValidateHeader->create(input_file=>$input);
ok($hv, "created command");

my $result = $hv->execute;
ok($result, "executed, header ok");

my $hv2 = Genome::Model::Tools::Sam::ValidateHeader->create(input_file=>$input_bad);
ok($hv2, "created command");

my $result2 = $hv2->execute;
ok(!defined($result2), "executed, successfully reported bad header");


