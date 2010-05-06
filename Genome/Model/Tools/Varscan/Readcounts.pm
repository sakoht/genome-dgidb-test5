
package Genome::Model::Tools::Varscan::Readcounts;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# Varscan::Somatic	Runs VarScan somatic pipeline on Normal/Tumor BAM files
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

class Genome::Model::Tools::Varscan::Readcounts {
	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		bam_file	=> { is => 'Text', doc => "Path to BAM file", is_optional => 0 },
		variants_file	=> { is => 'Text', doc => "Path to variant positions file", is_optional => 0 },
		output_file	=> { is => 'Text', doc => "Path to output file" , is_optional => 0},
		min_coverage	=> { is => 'Text', doc => "Minimum base coverage to report readcounts [8]" , is_optional => 1},
		min_base_qual	=> { is => 'Text', doc => "Minimum base quality to count a read [30]" , is_optional => 1},
	],
};

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
    "Run the VarScan readcounts tool"                 
}

sub help_synopsis {
    return <<EOS
Runs VarScan readcounts from BAM files
EXAMPLE:	gmt varscan readcounts --bam-file [sample.bam] --variants-file [variants.tsv] --output-file readcounts.txt ...
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
	my $reference = Genome::Config::reference_sequence_directory() . '/NCBI-human-build36/all_sequences.fa';
	my $variants_file = $self->variants_file;
	my $output_file = $self->output_file;
	

	if(-e $bam_file)
	{
		## Prepare pileup commands ##
		
		my $pileup = "samtools pileup -f $reference $bam_file";
		my $cmd = "bash -c \"java -classpath ~dkoboldt/Software/VarScan net.sf.varscan.VarScan readcounts <\($pileup\) --variants-file $variants_file --output-file $output_file\"";
		system($cmd);
	}
	else
	{
		die "Error: One of your BAM files doesn't exist!\n";
	}
	
	
	return 1;                               # exits 0 for true, exits 1 for false (retval/exit code mapping is overridable)
}


1;

