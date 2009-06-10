#!/gsc/bin/perl

use strict;
use warnings;

use Test::More tests => 5;
use File::Compare;
use above 'Genome';

BEGIN {
        use_ok('Genome::Model::Tools::RefCov::Progression');
};

my $dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-RefCov/Progression';
my @subdirs = qw/00 01 02 03 04 05 06 07/;
my $data_file = 'progression.dat';
my $image_file = 'progression.png';

my $tmp_dir = File::Temp::tempdir('RefCov-Progression-'. $ENV{USER} .'-XXXX',DIR=>'/gsc/var/cache/testsuite/running_testsuites',CLEANUP=>1);

my @stats_files;
my $subdir_name;
for my $subdir (sort {$a <=> $b} @subdirs) {
    unless ($subdir_name) {
        $subdir_name = $subdir;
    } else {
        $subdir_name .= '_'. $subdir;
    }
    push @stats_files, $dir .'/'. $subdir_name .'/STATS.tsv';
}

my $output_image_file = $tmp_dir .'/'. $image_file;
my $expected_image_file = $dir .'/'. $image_file;
my $output_data_file = $tmp_dir .'/'. $data_file;
my $expected_data_file = $dir .'/'. $data_file;

my $progression_cmd = Genome::Model::Tools::RefCov::Progression->create(
                                                                    stats_files => \@stats_files,
                                                                    image_file => $output_image_file,
                                                                    output_file => $output_data_file,
                                                                );
isa_ok($progression_cmd,'Genome::Model::Tools::RefCov::Progression');

ok($progression_cmd->execute,'execute progression command');
# I think comparing the two files is inappropriate with image files, could be meta differences
ok(-s $output_image_file,'output image file exists with size');
ok(!compare($expected_data_file,$output_data_file),'output matches expected data file');

exit;
