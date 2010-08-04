
package Genome::Model::Tools::Varscan::Germline;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# Varscan::Germline	Runs VarScan to call and filter SNPs/indels
#					
#	AUTHOR:		Dan Koboldt (dkoboldt@genome.wustl.edu)
#
#	CREATED:	12/09/2009 by D.K.
#	MODIFIED:	12/29/2009 by D.K.
#
#	NOTES:	
#			
#####################################################################################################################################

use strict;
use warnings;

use FileHandle;

use Genome;                                 # using the namespace authorizes Class::Autouse to lazy-load modules under it

class Genome::Model::Tools::Varscan::Germline {
	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		bam_file	=> { is => 'Text', doc => "Path to Normal BAM file", is_optional => 0, is_input => 1 },
		output_snp	=> { is => 'Text', doc => "Basename for SNP output, eg. varscan.snp" , is_optional => 0, is_input => 1, is_output => 1},
		#output_snp_filtered   => { is => 'Text', doc => "Name for filtered SNP output" , calculate_from => ['output_snp'], calculate => q{ $output_snp . '.filter' }, is_input => 1, is_output => 1, is_mutable => 0,},
		output_snp_filtered   => { is => 'Text', doc => "Name for filtered SNP output, (calculated based upon output_snp)", is_input => 1, is_output => 1, is_optional => 1}, 
		output_indel	=> { is => 'Text', doc => "Basename for indel output, eg. varscan.indel" , is_optional => 0, is_input => 1, is_output => 1},
		output_indel_filtered   => { is => 'Text', doc => "Name for filtered indel output, (calculated based upon output_indel)", is_input => 1, is_output => 1, is_optional => 1},
		#output_indel_filtered   => { is => 'Text', doc => "Name for filtered indel output" , calculate_from => ['output_indel'], calculate => q{ $output_indel . '.filter' }, is_input => 1, is_output => 1, is_mutable => 0,}, 
		reference	=> { is => 'Text', doc => "Reference FASTA file for BAMs (default= genome model)" , is_optional => 1, is_input => 1},
		heap_space	=> { is => 'Text', doc => "Megabytes to reserve for java heap [1000]" , is_optional => 1, is_input => 1},
		varscan_params	=> { is => 'Text', doc => "Parameters to pass to VarScan [--min-coverage 8 --min-var-freq 0.10 --p-value 0.05]" , is_optional => 1, is_input => 1},
	],	

	has_param => [
		lsf_resource => { default_value => 'select[model!=Opteron250 && type==LINUX64 && mem>4000] rusage[mem=4000]', doc => "LSF resource requirements [default: 64-bit, 4 GB RAM]", is_optional => 1},
       ],
};

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
    "Run the VarScan germline variant detection (SNPs and indels)"                 
}

sub help_synopsis {
    return <<EOS
Runs VarScan from BAM files
EXAMPLE:	gmt varscan germline --normal-bam [Normal.bam]  ...
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
	my $self = shift;

	## Get required parameters ##
	my $bam_file = $self->bam_file;
	my $output_snp = $self->output_snp;
	my $output_indel = $self->output_indel;

	## Get reference ##

	my $reference = Genome::Config::reference_sequence_directory() . '/NCBI-human-build36/all_sequences.fa';
	$reference = $self->reference if($self->reference);

	## Get VarScan parameters ##

     #TODO Remove this and replace with the calculated immutable properties above (when these UR changes are out).
     unless($self->output_snp_filtered) {
         $self->output_snp_filtered($self->output_snp . '.filter');
     }
     
     unless($self->output_indel_filtered) {
         $self->output_indel_filtered($self->output_indel . '.filter');
     }

	my $varscan_params = "--min-var-freq 0.10 --p-value 0.10 --somatic-p-value 0.01 --strand-filter 1"; #--min-coverage 8 --verbose 1
	$varscan_params = $self->varscan_params if($self->varscan_params);

	my $path_to_varscan = "java -classpath ~dkoboldt/Software/VarScan net.sf.varscan.VarScan";
	$path_to_varscan = "java -Xms" . $self->heap_space . "m -Xmx" . $self->heap_space . "m -classpath ~dkoboldt/Software/VarScan net.sf.varscan.VarScan" if($self->heap_space);

	if(-e $bam_file)
	{
		## Prepare pileup commands ##
		
		my $normal_pileup = "samtools view -b -u -q 10 $bam_file | samtools pileup -f $reference -";
		
		## Run VarScan ##

		my $cmd = "";

		## Call SNPs ##
		$cmd = "bash -c \"$path_to_varscan pileup2cns <\($normal_pileup\) --variants 1 $varscan_params >$output_snp.variants\"";
		print "RUN: $cmd\n";
		system($cmd);
		
		print "Parsing Variants into SNP/Indel files...\n";
		parse_variants_file("$output_snp.variants", $output_snp, $output_indel);

		## Filter Indels ##
          my $filtered_indel_file = $self->output_indel_filtered;
		$cmd = "bash -c \"$path_to_varscan filter $output_indel >$filtered_indel_file\"";
		print "RUN: $cmd\n";
		system($cmd);

		## Filter SNPs using Indels ##
		if(-e $output_snp && -e $filtered_indel_file)
		{
		     my $filtered_snp_file = $self->output_snp_filtered;
			$cmd = "bash -c \"$path_to_varscan filter $output_snp --indel-file $filtered_indel_file >$filtered_snp_file\"";
			print "RUN: $cmd\n";
			system($cmd);
		}
	}
	else
	{
		die "Error: One of your BAM files doesn't exist!\n";
	}
	
	
	return 1;                               # exits 0 for true, exits 1 for false (retval/exit code mapping is overridable)
}




################################################################################################
# Variants-to-SNPs-Indels
#
################################################################################################

sub parse_variants_file
{
	(my $variants_file, my $output_snp, my $output_indel) = @_;
	
	open(SNPS, ">$output_snp") or die "Can't open outfile: $!\n";
	open(INDELS, ">$output_indel") or die "Can't open outfile: $!\n";

	my $input = new FileHandle ($variants_file);	
	my $lineCounter = 0;

	while (<$input>)
	{
		chomp;
		my $line = $_;
		$lineCounter++;
		
		(my $chrom, my $position, my $ref, my $cns) = split(/\t/, $line);
		if($lineCounter == 1)
		{
			## Print header to both files ##
			
			print SNPS "$line\n";
			print INDELS "$line\n";
		}
		if(length($cns) > 1)
		{
			## Indel ##
			print INDELS "$line\n";
		}
		else
		{
			## SNP ##
			print SNPS "$line\n";
		}
	}
	
	close($input);

	close(SNPS);
	close(INDELS);

}

1;

