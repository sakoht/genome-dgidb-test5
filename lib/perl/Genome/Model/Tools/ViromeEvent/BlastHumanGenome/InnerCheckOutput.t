#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';
use Test::More;

use_ok('Genome::Model::Tools::ViromeEvent::BlastHumanGenome::InnerCheckOutput') or die;
#check blast dir .. testing on already completed, no-run, blast data so tool won't know if blast db is missing
ok( -s '/gscmnt/sata835/info/medseq/virome/blast_db/human_genomic/2009_07_09.humna_genomic', "Blast db exists");

my $file_to_run = '/gscmnt/sata420/info/testsuite_data/Genome-Model-Tools-ViromeScreening/Titanium17/Titanium17_undecodable/Titanium17_undecodable.fa.cdhit_out.masked.goodSeq_HGblast/Titanium17_undecodable.fa.cdhit_out.masked.goodSeq_file0.fa';
ok( -s $file_to_run, "Test fasta file exists" ) or die;

my $done_file = '/gscmnt/sata420/info/testsuite_data/Genome-Model-Tools-ViromeScreening/Titanium17/Titanium17_undecodable/Titanium17_undecodable.fa.cdhit_out.masked.goodSeq_HGblast/Titanium17_undecodable.fa.cdhit_out.masked.goodSeq_file0.HGblast.out';
ok( -s $done_file, "Blast completed file exists" ) or die; #otherwise will kick off blast which could take a long time

my $temp_dir = Genome::Utility::FileSystem->create_temp_directory();

my $c = Genome::Model::Tools::ViromeEvent::BlastHumanGenome::InnerCheckOutput->create(
    file_to_run => $file_to_run,
    logfile => $temp_dir.'/foo.txt',
    );
ok( $c, "Created blast human genome event" ) or die;

ok( $c->execute, "Successfully executed event" );

done_testing();

exit;
