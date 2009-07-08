#!/gsc/bin/perl

use strict;
use warnings;

use lib '/gscuser/edemello/svn/fresh4/trunk/Genome/Model/Tools/';
use above 'Genome';
use Test::More tests => 3;


BEGIN {use_ok('Genome::Model::Tools::ContaminationScreen::3730');}

my %params;
$params{input_file} = '/gsc/var/tmp/fasta/3730/test.fna';
$params{output_file} = '/gsc/var/tmp/fasta/3730/test_output.fna';
$params{database} = '/gsc/var/lib/reference/set/2809160070/blastdb/blast';

my $hcs_3730 = Genome::Model::Tools::ContaminationScreen::3730->create(%params);

isa_ok($hcs_3730, 'Genome::Model::Tools::ContaminationScreen::3730');

ok($hcs_3730->execute, "3730 executing");




