#!/usr/bin/env perl
use strict;
use warnings;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = "1";
$ENV{UR_DBI_NO_COMMIT} = "1";
use above "Genome";
use Test::More tests => 2;
use File::Temp;

my $tumor_bam = '/gsc/var/cache/testsuite/data/Genome-Model-Somatic-Command-RunPindel/flank_tumor_sorted.bam';
my $normal_bam = '/gsc/var/cache/testsuite/data/Genome-Model-Somatic-Command-RunPindel/flank_normal_sorted.bam';

my $output_dir = Genome::Sys->base_temp_directory();

ok(-d $output_dir, 'Found temp dir for test output.');


my $result = Genome::Model::Somatic::Command::RunPindel->create( tumor_bam => $tumor_bam, normal_bam => $normal_bam, output_directory => $output_dir);

ok($result, 'able to create run-pindel object, preparing to run');


=cut
$ENV{NO_LSF}="1";
my $answer = $result->execute();


my @files = glob($output_dir);

for my $file (@files){
    

ok(-s $output_dir."/tier1_annoatated.csv", 'found annoatation output.');


#is($disk->owner_id, $i->id, "allocation owner ID matches imported instrument data id");

#ok(-e $i->data_directory, "output directory is present");
=cut0


