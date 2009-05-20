
package Genome::Model::Tools::Analysis::Solexa::ContigResults;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# ContigResults - Get the variant contig results
#					
#	AUTHOR:		Dan Koboldt (dkoboldt@watson.wustl.edu)
#
#	CREATED:	04/20/2009 by D.K.
#	MODIFIED:	04/20/2009 by D.K.
#
#	NOTES:	
#			
#####################################################################################################################################

use strict;
use warnings;

use FileHandle;
use Bio::DB::Fasta;

my $ref_dir = "/gscmnt/sata180/info/medseq/biodb/shared/Hs_build36_mask1c/";

use Genome;                                 # using the namespace authorizes Class::Autouse to lazy-load modules under it

class Genome::Model::Tools::Analysis::Solexa::ContigResults {
	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		variants_file	=> { is => 'Text', doc => "File of SNPs in chrom, pos, ref, var TSV format" },
		alignments_file => { is => 'Text', doc => "Alignments (Bowtie) to variant contigs" },
		output_file	=> { is => 'Text', doc => "Optional output file", is_optional => 1},
	],
};

#, is_optional => 1

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
    "Build reference and variant contigs for alignment purposes"                 
}

sub help_synopsis {
    return <<EOS
This command builds reference and variant contigs for alignment purposes
EXAMPLE:	gt analysis variant-contigs --variants-file test.snps
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
	my $variants_file = $self->variants_file;
	my $alignments_file = $self->alignments_file;
	my $output_file = $self->output_file;

	if(!(-e $variants_file))
	{
		die "Error: Variants file not found!\n";
	}

	if(!(-e $alignments_file))
	{
		die "Error: Alignments file not found!\n";
	}

	my %read_counts = ();

	print "Parsing the alignments file...\n";

	## Parse the alignments file ##

 	my $input = new FileHandle ($alignments_file);
	my $lineCounter = 0;
	
	while (<$input>)
	{
		chomp;
		my $line = $_;
		$lineCounter++;		
	
		my @lineContents = split(/\t/, $line);
		my $align_strand = $lineContents[1];
		my $contig_name = $lineContents[2];
		if($contig_name)
		{		
			$read_counts{$contig_name}++;
		}
	}
	
	close($input);

#	foreach my $contig (keys %read_counts)
#	{
#		print "$read_counts{$contig}\t$contig\n";
#	}


	if($output_file)
	{
		open(OUTFILE, ">$output_file") or die "Can't open outfile: $!\n";
		print OUTFILE "chrom\tposition\tref\tvar\tref_reads\tvar_reads\n";
	}

	print "Parsing the variants file...\n";

	## Parse the variants file ##

 	$input = new FileHandle ($variants_file);
	$lineCounter = 0;
	
	while (<$input>)
	{
		chomp;
		my $line = $_;
		$lineCounter++;		
	
		if($lineCounter > 1)
		{
			(my $chromosome, my $position, my $allele1, my $allele2) = split(/\t/, $line);
			
			if($chromosome && $chromosome ne "chromosome" && $chromosome ne "ref_name")
			{
				my $contig_name_ref = $chromosome . "_" . $position . "_" . $allele1 . "_" . $allele2 . "_ref";
				my $contig_name_var = $chromosome . "_" . $position . "_" . $allele1 . "_" . $allele2 . "_var";

				## Get the read counts for each contig ##
				
				my $reads_ref = $read_counts{$contig_name_ref};
				my $reads_var = $read_counts{$contig_name_var};
				$reads_ref = 0 if(!$reads_ref);
				$reads_var = 0 if(!$reads_var);
				
				print "$chromosome\t$position\t$allele1\t$allele2\t$reads_ref\t$reads_var\n";
				print OUTFILE "$chromosome\t$position\t$allele1\t$allele2\t$reads_ref\t$reads_var\n" if($output_file);
			}
		}
	}
	
	close($input);

 
	return 1;                               # exits 0 for true, exits 1 for false (retval/exit code mapping is overridable)
}



1;

