#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use Genome::Model::Tools::BWA::AlignReads;
use Test::More;
#tests => 1;

if (`uname -a` =~ /x86_64/){
    plan tests => 7;
} else{
    plan skip_all => 'Must run on a 64 bit machine';
}

my $expected_output = 3;

my $ref_seq = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BWA-AlignReads/reference-sequence/all_sequences.fa";
my $files_to_align = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BWA-AlignReads/single-solexa";
my $unaligned = "unaligned.out";
my $aligner_log = "aligner.log";
my $sol_flag = "y";
my $output_dir = File::Temp::tempdir(CLEANUP => 1);
my $force_fragments = 1;

##############
#TODO:  Subbing out aligner tool to reduce loc 
#my $asub = execute_alignment(ref_seq=>"fooseq");
#print 'asub: '.$asub;
#############

 
#Case 1: single read 
my $aligner = Genome::Model::Tools::BWA::AlignReads->create(
                                                            ref_seq_file => $ref_seq,
                                                            files_to_align_path => $files_to_align,
                                                            alignment_file => $output_dir .'/single_read.bam',
                                                            aligner_output_file => $output_dir .'/single_read.out',
                                                            unaligned_reads_file => $output_dir .'/single_read.unaligned',
                                                        );
is($aligner->use_version,'0.4.9','using 0.4.9 version of bwa');


#execute the tool 
ok($aligner->execute,'AlignReads execution, single read solexa input.');

#check the number of files in the output directory, should be 2.
my @listing = glob($output_dir.'/*');
ok( scalar(@listing) eq $expected_output, "Number of output files expected = ".$expected_output );



#Case 2: paired end 

#get a new output dir
$output_dir = File::Temp::tempdir(CLEANUP => 1);
#get new input test data
$files_to_align = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BWA-AlignReads/paired-solexa";
#Add a pipe delimited test eventually...
#$files_to_align = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BWA-AlignReads/paired-solexa/s_1_1_sequence_test.txt|/gsc/var/cache/testsuite/data/Genome-Model-Tools-BWA-AlignReads/paired-solexa/s_1_2_sequence_test.txt";

$aligner = Genome::Model::Tools::BWA::AlignReads->create(
							 ref_seq_file => $ref_seq,
                                                         files_to_align_path => $files_to_align,
                                                         alignment_file => $output_dir .'/paired-solexa.map',
                                                         aligner_output_file => $output_dir .'/paired-solexa.out',
                                                         unaligned_reads_file => $output_dir .'/paired-solexa.unaligned',
							);

#execute the tool 
$DB::single = 1;
ok($aligner->execute,'AlignReads execution, paired read solexa input.');
$DB::single = 1;

#check the number of files in the output directory, should be 2.
@listing = glob($output_dir.'/*');
ok( scalar(@listing) eq $expected_output, "Number of output files expected = ".$expected_output );


#Case 3: paired end, force fragment
#get a new output dir

#local testing
$output_dir = File::Temp::tempdir(CLEANUP => 1);
#$output_dir = "output";

#get new input test data
$files_to_align = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-Maq-AlignReads/paired-solexa";

$aligner = Genome::Model::Tools::BWA::AlignReads->create(
							 ref_seq_file => $ref_seq,
                                                         files_to_align_path => $files_to_align,
							 force_fragments => $force_fragments,
                                                         alignment_file => $output_dir .'/paired-solexa-frag.map',
                                                         aligner_output_file => $output_dir .'/paired-solexa-frag.out',
                                                         unaligned_reads_file => $output_dir .'/paired-solexa-frag.unaligned',
							);

#execute the tool 
ok($aligner->execute,'AlignReads execution, paired read solexa input, forcing fragments.');

#check the number of files in the output directory, should be 2.
@listing = glob($output_dir.'/*');
ok( scalar(@listing) eq $expected_output, "Number of output files expected = ".$expected_output );

