#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use above 'Genome';
use Genome::Model::Tools::Picard::SamToFastq;
use Test::More tests => 4;
use File::Temp;
use Path::Class qw(dir file);

# data here is first 100 lines from lane 1 of
# /gscmnt/sata604/hiseq2000/100218_P21_0393_AFC20GF1/Data/Intensities/Basecalls/GERALD_30-03-2010_lims
# see FastqToSam.t
my $dir = dir(
    '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Picard-FastqToSam');

my $tmpdir = dir( File::Temp::tempdir( CLEANUP => 1 ) );
my $fq1    = $tmpdir->file('s_1_1_sequence.txt');
my $fq2    = $tmpdir->file('s_1_2_sequence.txt');
my $fq3    = $tmpdir->file('s_1_sequence.txt');
my $bam    = $dir->file('gerald_20GF1_1.bam');

my $cmd_1  = Genome::Model::Tools::Picard::SamToFastq->create(
    input  => $bam . '',
    fastq  => $fq1 . '',
    fastq2 => $fq2 . '',
    fragment_fastq => $fq3 . '',
    no_orphans => 1,
);
isa_ok( $cmd_1, 'Genome::Model::Tools::Picard::SamToFastq' );
ok( $cmd_1->execute, 'execute' );
ok( -s $fq1,         'output file is non-zero' );
ok( -s $fq2,         'output file is non-zero' );

$tmpdir->rmtree;

