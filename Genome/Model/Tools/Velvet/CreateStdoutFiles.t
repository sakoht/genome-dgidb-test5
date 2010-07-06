#!/gsc/bin/perl

use strict;
use warnings;

use Cwd;
use above "Genome";
use Test::More;

my $module = 'Genome-Model-Tools-Assembly-CreateOutputFiles2';
my $data_dir = "/gsc/var/cache/testsuite/data/$module";

ok(-d $data_dir, "Found data directory: $data_dir");

my $temp_dir = Genome::Utility::FileSystem->create_temp_directory();

#make edit_dir in temp_dir
mkdir $temp_dir.'/edit_dir';
ok(-d $temp_dir.'/edit_dir', "made edit_dir in temp test_dir");

#copy needed input files to temp dir
foreach my $file ('contigs.fa', 'input.fastq', 'Sequences', 'velvet_asm.afg') {
    my $test_file = $data_dir.'/'.$file;
    ok(-s $test_file, "Test $file file exists");
    my $new_file = $temp_dir.'/'.$file;
    ok(File::Copy::copy($test_file, $temp_dir),"Copied test $file to temp dir");
    ok(-s $new_file, "$file exists temp_dir");
}

#copy ace file
my $ace_file = $data_dir.'/edit_dir/velvet_asm.ace';
ok(-s $ace_file, "Test velvet_asm.ace file exists");
ok(File::Copy::copy($ace_file, $temp_dir.'/edit_dir'), "Copied test velvet_asm.ace to temp dir");

#create test output files
my $ec = system("chdir $temp_dir; gmt velvet create-stdout-files --directory $temp_dir --input-fastq-file $temp_dir".'/input.fastq');
ok($ec == 0, "Command ran successfully");

#make sure test suite and tmp dirs are the same
my $dir_test = $data_dir.'/edit_dir';
my $dir_temp = $temp_dir.'/edit_dir';

my @dir_diff = `diff -r --brief $dir_test $dir_temp | grep -v Log | grep -v timing`;
is(scalar(@dir_diff), 2, "Directory contents match except for 2 zipped files and extra contigs files") or diag(@dir_diff);

#check two zipped files separately
my $test_fasta = $data_dir.'/edit_dir/input.fasta.gz';
my $test_qual = $data_dir.'/edit_dir/input.fasta.qual.gz';

my $temp_fasta = $temp_dir.'/edit_dir/input.fasta.gz';
my $temp_qual = $temp_dir.'/edit_dir/input.fasta.qual.gz';

my @fasta_diff = `zdiff $test_fasta $temp_fasta`;
is(scalar (@fasta_diff), 0, "Zipped fasta files match") or diag(@fasta_diff);

my @qual_diff = `zdiff $test_qual $temp_qual`;
is(scalar (@qual_diff), 0, "Zipped qual files match") or diag(@qual_diff);

done_testing();

exit;
