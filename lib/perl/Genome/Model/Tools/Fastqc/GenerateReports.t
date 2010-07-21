#!/gsc/bin/perl

use strict;
use warnings;

use Test::More tests => 3;

use above 'Genome';

use_ok('Genome::Model::Tools::Fastqc::GenerateReports');
my $tmp_dir = Genome::Utility::FileSystem->create_temp_directory;
my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Fastqc-GenerateReports';

my @fastq_files = ($data_dir .'/s_2_1_sequence.txt',  $data_dir .'/s_2_2_sequence.txt');
my $fastq_files = join(',',@fastq_files);
my $fastqc = Genome::Model::Tools::Fastqc::GenerateReports->create(
    fastq_files => $fastq_files,
    report_directory => $tmp_dir,
);
isa_ok($fastqc,'Genome::Model::Tools::Fastqc::GenerateReports');
ok($fastqc->execute,'execute command '. $fastqc->command_name);

#TODO: Add file comparsion or another test to verify output is complete and correct

exit;
