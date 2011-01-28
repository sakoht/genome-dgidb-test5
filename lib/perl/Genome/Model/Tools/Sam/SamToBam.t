#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";

use Test::More;
use File::Temp;
use File::Copy;
use File::Compare;

BEGIN {
    if (`uname -a` =~ /x86_64/){
        plan tests => 4;
    }
    else{
        plan skip_all => 'Must run on a 64 bit machine';
    }

    use_ok('Genome::Model::Tools::Sam::SamToBam');
}

my $root_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Sam-SamToBam';

my $tmp_dir  = File::Temp::tempdir(
    'SamToBam-XXXXX',
    DIR => '/gsc/var/cache/testsuite/running_testsuites',
    CLEANUP => 1,
);

copy "$root_dir/source-1.sam", $tmp_dir;
my $sam_file = "$tmp_dir/source-1.sam";

my $to_bam = Genome::Model::Tools::Sam::SamToBam->create(
    sam_file => $sam_file,                                                      
    keep_sam => 1,
    fix_mate => 1,
    ref_list => "$root_dir/read_index.fai"
);

isa_ok($to_bam,'Genome::Model::Tools::Sam::SamToBam');
ok($to_bam->execute,'bam executed ok');

$DB::single = 1;
is(compare("$tmp_dir/source-1.bam", "$root_dir/expected-1-update.bam"), 0, 'Bam file was created ok');


exit;

