#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";

use Test::More tests => 4;
use File::Temp;
use File::Copy;
use File::Compare;

BEGIN {
    use_ok('Genome::Model::Tools::Sam::IndelFilter');
}

my $root_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Sam/IndelFilter';
my $run_dir  = '/gsc/var/cache/testsuite/running_testsuites';

my $tmp_dir  = File::Temp::tempdir(
    "IndelFilter_XXXXXX", 
    DIR     => $run_dir,
    CLEANUP => 1,
);

my $indel_file = "$root_dir/test.sam.indel";
my $out_file = "$tmp_dir/test.sam.indel.filtered";
my $ori_file = "$root_dir/test.sam.indel.filtered.ori";

my $filter = Genome::Model::Tools::Sam::IndelFilter->create(
    indel_file => $indel_file,                                                      
    out_file   => $out_file,
);

isa_ok($filter,'Genome::Model::Tools::Sam::IndelFilter');
ok($filter->execute,'executed ok');

cmp_ok(compare($out_file, $ori_file), '==', 0, 'Sam indelfilter file was created ok');

exit;

