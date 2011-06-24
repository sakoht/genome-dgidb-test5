package Genome::Model::Tools::Varscan::PullOneTwoBpIndels;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# PullOneTwoBpIndels - Generate lists of 1-2 bp and 3+ indels, run GATK recalibration, and then sort and index bams
#					
#	AUTHOR:		Will Schierding (wschierd@genome.wustl.edu)
#
#	CREATED:	11/29/2010 by W.S.
#	MODIFIED:	11/29/2010 by W.S.
#
#	NOTES:	
#			
#####################################################################################################################################

use strict;
use warnings;

use FileHandle;
use File::Basename; #for file name parsing
use Genome;                                 # using the namespace authorizes Class::Autouse to lazy-load modules under it

class Genome::Model::Tools::Varscan::PullOneTwoBpIndels {
	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		project_name	=> { is => 'Text', doc => "Name of the project i.e. ASMS" , is_optional => 1},
		file_list	=> { is => 'Text', doc => "File of indel files to include, 1 name per line, tab delim, no headers. Should be chr start stop ref var blahhhhhhhhhhhh." , is_optional => 0},
		small_indel_outfile	=> { is => 'Text', doc => "File of small indels to be realigned" , is_optional => 0},
		large_indel_outfile	=> { is => 'Text', doc => "File of large indels to be realigned" , is_optional => 1},
		tumor_bam	=> { is => 'Text', doc => "Tumor Bam File (Validation Bam)" , is_optional => 0},
		normal_bam	=> { is => 'Text', doc => "Normal Bam File (Validation Bam)" , is_optional => 0},
		reference_fasta	=> { is => 'Text', doc => "Reference Fasta" , is_optional => 0, default => "/gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/all_sequences.fa"},
		output_indel	=> { is => 'Text', doc => "gmt varscan validate input" , is_optional => 0},
		output_snp	=> { is => 'Text', doc => "gmt varscan validate input" , is_optional => 0},
		final_output_file	=> { is => 'Text', doc => "process-validation-indels output file" , is_optional => 0},
		skip_if_output_present	=> { is => 'Boolean', doc => "Skip Creating new Bam Files if they exist" , is_optional => 1, default => ""},
	        realigned_bam_file_directory => { is => 'Text', doc => "Where to dump the realigned bam file", is_optional => 0},
        	normal_purity => { is => 'Float', doc => "Normal purity param to pass to varscan", is_optional => 0, default => 1},
        	min_var_frequency => { is => 'Float', doc => "Minimum variant frequency to pass to varscan", is_optional => 0, default => 0.08},
	],
};

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
    "Generate lists of 1-2 bp and 3+ indels, run GATK recalibration, and then sort and index bams"
}

sub help_synopsis {
    return <<EOS
Generate lists of 1-2 bp and 3+ indels, run GATK recalibration, and then sort and index bams
EXAMPLE:	gmt varscan pull-one-two-bp-indels
EOS
}

sub help_detail {                           # this is what the user will see with the longer version of help. <---
    return <<EOS 

EOS
}


################################################################################################
# Execute - the main program logic
#
################################################################################################

sub execute {                               # replace with real execution logic.
    $DB::single = 1;
	my $self = shift;
	my $project_name = $self->project_name;
	my $small_indel_list = $self->small_indel_outfile;
	my $large_indel_list = $self->large_indel_outfile;
	my $file_list_file = $self->file_list;
	my $normal_bam = $self->normal_bam;
	my $tumor_bam = $self->tumor_bam;
	my $reference = $self->reference_fasta;
	my $output_indel = $self->output_indel;
	my $output_snp = $self->output_snp;
	my $final_output_file = $self->final_output_file;
	my $skip_if_output_present = $self->skip_if_output_present;

	unless ($small_indel_list =~ m/\.bed/i) {
		die "Indel File Must end in .bed";
	}

	my $small_indel_list_nobed = $small_indel_list;
	$small_indel_list_nobed =~ s/\.bed//;
	$small_indel_list_nobed = "$small_indel_list_nobed.txt";

	my $large_indel_list_nobed = $large_indel_list;
	$large_indel_list_nobed =~ s/\.bed//;
	$large_indel_list_nobed = "$large_indel_list_nobed.txt";

        my $realigned_bam_file_directory = $self->realigned_bam_file_directory;
	my $realigned_normal_bam_file = basename($normal_bam,qr{\.bam});
    
	$realigned_normal_bam_file = "$realigned_bam_file_directory/$realigned_normal_bam_file.realigned.bam";

	my $realigned_tumor_bam_file = basename($tumor_bam,qr{\.bam});
	$realigned_tumor_bam_file = "$realigned_bam_file_directory/$realigned_tumor_bam_file.realigned.bam";

	## Open the outfiles ##
	my $bed_indel_outfile = $small_indel_list;
	my $nobed_indel_outfile = $small_indel_list_nobed;
	open(INDELS_OUT, ">$bed_indel_outfile") or die "Can't open output file: $!\n";
	open(NOBED_INDELS_OUT, ">$nobed_indel_outfile") or die "Can't open output file: $!\n";
	my $large_bed_indel_outfile = $large_indel_list;
	my $large_nobed_indel_outfile = $large_indel_list_nobed;
	open(LARGE_INDELS_OUT, ">$large_bed_indel_outfile") or die "Can't open output file: $!\n";
	open(LARGE_NOBED_INDELS_OUT, ">$large_nobed_indel_outfile") or die "Can't open output file: $!\n";
	my $file_input = new FileHandle ($file_list_file);
    unless($file_input) {
        $self->error_message("Unable to open $file_list_file");
        return;
    }

	while (my $file = <$file_input>) {
		chomp($file);
		my $indel_input = new FileHandle ($file);
        unless($indel_input) {
            $self->error_message("Unable to open $file");
            return;
        }

		while (my $line = <$indel_input>) {
			chomp($line);
			my ($chr, $start, $stop, $ref, $var, @everything_else) = split(/\t/, $line);
			my $size;
			if ($ref =~ m/\//) {
				my $split = $ref;
				($ref, $var) = split(/\//, $split);
			}
			if ($ref eq '-' || $ref eq '0') { #ins
				#count number of bases inserted
				$size = length($var);
			}
			elsif ($var eq '-' || $var eq '0') { #del
				$size = length($ref);
			}
			else {
				print "Line $line in file $file has wrong insertion or deletion nomenclature. Either ref or var should be 0 or -";
				$size = 0;  #this will include this indel despite its wrongness
			}
			if ( $size > 0 && $size <= 2) {
				my $bedstart = ($start - 1);
				print INDELS_OUT "$chr\t$bedstart\t$stop\t$ref\t$var\n";
				print NOBED_INDELS_OUT "$chr\t$start\t$stop\t$ref\t$var\n";
			}
			elsif ( $size > 2) {
				my $bedstart = ($start - 1);
				print LARGE_INDELS_OUT "$chr\t$bedstart\t$stop\t$ref\t$var\n";
				print LARGE_NOBED_INDELS_OUT "$chr\t$start\t$stop\t$ref\t$var\n";
			}
		}
		close($indel_input);
	}
	close($file_input);

    my $min_freq = $self->min_var_frequency;
    my $normal_purity = $self->normal_purity;
    my $varscan_params = "--validation 1 --somatic-p-value 1.0e-02 --p-value 0.10 --min-coverage 8 --min-var-freq $min_freq --normal-purity $normal_purity";

	my $bsub = 'bsub -q long -R "select[model!=Opteron250 && type==LINUX64 && mem>16000 && tmp>10000] rusage[mem=16000, tmp=10000]" -M 16000000 ';
	my ($jobid1, $jobid2, $jobid3, $jobid4, $jobid5, $jobid6);
	if ($skip_if_output_present && -s $realigned_normal_bam_file && -s $realigned_tumor_bam_file) {
		my $jobid1 = `$bsub -J varscan_validation \'gmt varscan validation --normal-bam $realigned_normal_bam_file --tumor-bam $realigned_tumor_bam_file --output-indel $output_indel --output-snp $output_snp --varscan-params "$varscan_params"\'`;
		   $jobid1=~/<(\d+)>/;
		   $jobid1= $1;
		   print "$jobid1\n";

           #add in email of final job completion. cause I like those
           my $user = $ENV{USER};

		my $jobid2 = `$bsub -N -u $user\@genome.wustl.edu -J varscan_process_validation -w \'ended($jobid1)\' \'gmt varscan process-validation-indels --validation-indel-file $output_indel --validation-snp-file $output_snp --variants-file $small_indel_list_nobed --output-file $final_output_file\'`;
		   $jobid2=~/<(\d+)>/;
		   $jobid2= $1;
		   print "$jobid2\n";
	}
	else{
#/gscuser/dkoboldt/Software/GATK/GenomeAnalysisTK-1.0.4418/GenomeAnalysisTK.jar /gsc/scripts/pkg/bio/gatk/GenomeAnalysisTK-1.0.5336/GenomeAnalysisTK.jar
		my $bsub_normal_output = "$realigned_bam_file_directory/realignment_normal.out";
		my $bsub_normal_error = "$realigned_bam_file_directory/realignment_normal.err";
		my $jobid1 = `$bsub -J $realigned_normal_bam_file -o $bsub_normal_output -e $bsub_normal_error \'java -Xmx16g -Djava.io.tmpdir=/tmp -jar /gsc/pkg/bio/gatk/GenomeAnalysisTK-1.0.5777/GenomeAnalysisTK.jar -et NO_ET -T IndelRealigner -targetIntervals $small_indel_list -o $realigned_normal_bam_file -I $normal_bam -R $reference  --targetIntervalsAreNotSorted\'`;
		   $jobid1=~/<(\d+)>/;
		   $jobid1= $1;
		   print "$jobid1\n";
		my $bsub_tumor_output = "$realigned_bam_file_directory/realignment_tumor.out";
		my $bsub_tumor_error = "$realigned_bam_file_directory/realignment_tumor.err";
		my $jobid2 = `$bsub -J $realigned_tumor_bam_file -o $bsub_tumor_output -e $bsub_tumor_error \'java -Xmx16g -Djava.io.tmpdir=/tmp -jar /gsc/pkg/bio/gatk/GenomeAnalysisTK-1.0.5777/GenomeAnalysisTK.jar -et NO_ET -T IndelRealigner -targetIntervals $small_indel_list -o $realigned_tumor_bam_file -I $tumor_bam -R $reference --targetIntervalsAreNotSorted\'`;
		   $jobid2=~/<(\d+)>/;
		   $jobid2= $1;
		   print "$jobid2\n";

		my $jobid5 = `$bsub -J bamindex_normal -w \'ended($jobid1)\' \'samtools index $realigned_normal_bam_file\'`;
		   $jobid5=~/<(\d+)>/;
		   $jobid5= $1;
		   print "$jobid5\n";
		my $jobid6 = `$bsub -J bamindex_tumor -w \'ended($jobid2)\' \'samtools index $realigned_tumor_bam_file\'`;
		   $jobid6=~/<(\d+)>/;
		   $jobid6= $1;
		   print "$jobid6\n";
		my $jobid7 = `$bsub -J varscan_validation -w \'ended($jobid5) && ended($jobid6)\' \'gmt varscan validation --normal-bam $realigned_normal_bam_file --tumor-bam $realigned_tumor_bam_file --output-indel $output_indel --output-snp $output_snp --varscan-params "$varscan_params"\'`;
		   $jobid7=~/<(\d+)>/;
		   $jobid7= $1;
		   print "$jobid7\n";

           #add in email of final job completion. cause I like those
           my $user = $ENV{USER};


		my $jobid8 = `$bsub -N -u $user\@genome.wustl.edu -J varscan_process_validation -w \'ended($jobid7)\' \'gmt varscan process-validation-indels --validation-indel-file $output_indel --validation-snp-file $output_snp --variants-file $small_indel_list_nobed --output-file $final_output_file\'`;
		   $jobid8=~/<(\d+)>/;
		   $jobid8= $1;
		   print "$jobid8\n";
	}

	return 1;
}

















