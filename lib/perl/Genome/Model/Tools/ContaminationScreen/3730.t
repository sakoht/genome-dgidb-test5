#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';
use Test::More tests => 2;
use FindBin qw($Bin);

BEGIN {use_ok('Genome::Model::Tools::ContaminationScreen::3730');}

my $datadir = $Bin . '/3730.t.d';

my %params;
$params{input_file} = $datadir . '/test.fna';
$params{output_file} = $datadir . '/test_output.fna';
$params{database} = '/gsc/var/lib/reference/set/2809160070/blastdb/blast';

my $hcs_3730 = Genome::Model::Tools::ContaminationScreen::3730->create(%params);

isa_ok($hcs_3730, 'Genome::Model::Tools::ContaminationScreen::3730');




