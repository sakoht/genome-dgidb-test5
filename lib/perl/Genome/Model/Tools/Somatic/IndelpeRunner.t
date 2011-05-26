#!/usr/bin/env perl

use strict;
use warnings;

use above "Genome";
use Test::More;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

BEGIN {
    my $archos = `uname -a`;
    if ($archos !~ /64/) {
        plan skip_all => "Must run from 64-bit machine";
    } else {
        plan tests => 8;
    }
};

use_ok( 'Genome::Model::Tools::Somatic::IndelpeRunner');

my $test_input_dir      = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Somatic-IndelpeRunner/';

my $bam_file            = $test_input_dir . 'tumor.tiny.bam';
my $ref_seq_file        = Genome::Config::reference_sequence_directory() . '/NCBI-human-build36/all_sequences.fa'; #The real one

my $test_output_dir     = File::Temp::tempdir('Genome-Model-Tools-Somatic-IndelpeRunner-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
$test_output_dir .= '/';

my $output_dir          = $test_output_dir . 'output';
$output_dir .= '/';

my $snp_output_file     = $output_dir . 'snp.out';
my $filtered_snp_file   = $output_dir . 'filtered_snp.out';
my $indel_output_file   = $output_dir . 'indel.out';
my $filtered_indel_file = $output_dir . 'filtered_indel.out';

my $indelpe_runner      = Genome::Model::Tools::Somatic::IndelpeRunner->create(
    bam_file            => $bam_file,
    ref_seq_file        => $ref_seq_file,
    output_dir          => $output_dir,
    snp_output_file     => $snp_output_file,
    filtered_snp_file   => $filtered_snp_file,
    indel_output_file   => $indel_output_file,
    filtered_indel_file => $filtered_indel_file
);

ok($indelpe_runner, 'created IndelpeRunner object');
ok($indelpe_runner->execute(), 'executed IndelpeRunner object');

ok(-d $output_dir, 'output directory created');

ok(-s $snp_output_file, 'generated snp output');
ok(-f $filtered_snp_file, 'generated (possibly empty) filtered snp output');
ok(-s $indel_output_file, 'generated indel output');
ok(-f $filtered_indel_file, 'generated (possibly empty) filtered indel output');
