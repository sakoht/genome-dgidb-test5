
package Genome::Model::Tools::SnpArray::ValidateGermlineCalls;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# SearchRuns - Search the database for runs
#					
#	AUTHOR:		Dan Koboldt (dkoboldt@watson.wustl.edu)
#
#	CREATED:	04/01/2009 by D.K.
#	MODIFIED:	04/01/2009 by D.K.
#
#	NOTES:	
#			
#####################################################################################################################################

use strict;
use warnings;

use FileHandle;

use Genome;                                 # using the namespace authorizes Class::Autouse to lazy-load modules under it

class Genome::Model::Tools::SnpArray::ValidateGermlineCalls {
	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		genotype_file	=> { is => 'Text', doc => "Three-column file of genotype calls chrom, pos, genotype", is_optional => 0, is_input => 1 },
		variant_file	=> { is => 'Text', doc => "Variant calls in SAMtools pileup-consensus format", is_optional => 0, is_input => 1 },
		sample_name	=> { is => 'Text', doc => "Name of the sample for output file", is_optional => 1, is_input => 1 },
		min_depth_het	=> { is => 'Text', doc => "Minimum depth to compare a het call [4]", is_optional => 1, is_input => 1},
		min_depth_hom	=> { is => 'Text', doc => "Minimum depth to compare a hom call [8]", is_optional => 1, is_input => 1},
		verbose	=> { is => 'Text', doc => "Turns on verbose output [0]", is_optional => 1, is_input => 1},
		flip_alleles 	=> { is => 'Text', doc => "If set to 1, try to avoid strand issues by flipping alleles to match", is_optional => 1, is_input => 1},
		output_file	=> { is => 'Text', doc => "Output file for QC result", is_optional => 1, is_input => 1}
	],
};

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
    "Validates VarScan germline calls using SNP array data"                 
}

sub help_synopsis {
    return <<EOS
This command validates VarScan germline calls using SNP array data
EXAMPLE:	gmt snp-array validate-germline-calls --genotype-file affy.genotypes --variant-file lane1.var
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
	my $variant_file = $self->variant_file;
	my $genotype_file = $self->genotype_file;

	my $min_depth_hom = 4;
	my $min_depth_het = 8;
	$min_depth_hom = $self->min_depth_hom if($self->min_depth_hom);
	$min_depth_het = $self->min_depth_het if($self->min_depth_het);

	## Assign a sample name ##

	my $sample_name = "Sample";

	if($self->sample_name)
	{
		$sample_name = $self->sample_name;
	}
	elsif($self->variant_file)
	{
		$sample_name = $self->variant_file if($self->variant_file);	
	}

	print "Loading genotypes from $genotype_file...\n" if($self->verbose);
	my %genotypes = load_genotypes($genotype_file);

	
	if($self->output_file)
	{
		open(OUTFILE, ">" . $self->output_file) or die "Can't open outfile: $!\n";
#		print OUTFILE "file\tnum_snps\tnum_with_genotype\tnum_min_depth\tnum_variant\tvariant_match\thom_was_het\thet_was_hom\thet_was_diff\tconc_variant\tconc_rare_hom\n";
		#num_ref\tref_was_ref\tref_was_het\tref_was_hom\tconc_overall
	}

	
	my %stats = ();
	$stats{'num_snps'} = $stats{'num_min_depth'} = $stats{'num_with_genotype'} = $stats{'num_with_variant'} = $stats{'num_variant_match'} = 0;
	$stats{'het_was_hom'} = $stats{'hom_was_het'} = $stats{'het_was_diff_het'} = $stats{'rare_hom_match'} = $stats{'rare_hom_total'} = 0;
	$stats{'num_ref_was_ref'} = $stats{'num_ref_was_hom'} = $stats{'num_ref_was_het'} = 0;


	print "Parsing variant calls in $variant_file...\n" if($self->verbose);

	my $input = new FileHandle ($variant_file);
	my $lineCounter = 0;

	my $verbose_output = "";

	while (<$input>)
	{
		chomp;
		my $line = $_;
		$lineCounter++;
		
		my @lineContents = split(/\t/, $line);
		my $chrom = $lineContents[0];
		my $position = $lineContents[1];
		my $ref_base = $lineContents[3];
		my $normal_reads1 = $lineContents[5];
		my $normal_reads2 = $lineContents[6];
		my $normal_call = $lineContents[8];

		my $tumor_reads1 = $lineContents[9];
		my $tumor_reads2 = $lineContents[10];
		my $tumor_call = $lineContents[12];

		my $normal_coverage = $normal_reads1 + $normal_reads2;
		my $tumor_coverage = $tumor_reads1 + $tumor_reads2;
		my $depth = 0;
		my $cns_call = "";
		
		if($normal_coverage > $tumor_coverage)
		{
			$cns_call = $normal_call;
			$depth = $normal_coverage;
		}
		else
		{
			$cns_call = $tumor_call;
			$depth = $tumor_coverage;
		}
		
		if(lc($chrom) =~ "chrom")
		{
			## Ignore header ##
		}
		else
		{
			## Only check SNP calls ##
	
			if($ref_base ne "*" && length($ref_base) == 1 && length($cns_call) == 1) #$ref_base ne $cns_call
			{
				## Get depth and consensus genotype ##
	
				my $cons_gt = "";
				$cons_gt = code_to_genotype($cns_call);							
				$cons_gt = sort_genotype($cons_gt);			
			
				$stats{'num_snps'}++;
				
#				warn "$stats{'num_snps'} lines parsed...\n" if(!($stats{'num_snps'} % 10000));
	
				my $key = "$chrom\t$position";
					
				if($genotypes{$key})
				{
					$stats{'num_with_genotype'}++;
					
					my $chip_gt = sort_genotype($genotypes{$key});

					if((is_homozygous($chip_gt) && $depth >= $min_depth_hom) || (is_heterozygous($chip_gt) && $depth >= $min_depth_het))
					{
						my $ref_gt = code_to_genotype($ref_base);

						$stats{'num_min_depth'}++;
					
						
						if($self->flip_alleles && $chip_gt ne $cons_gt)
						{
							$chip_gt = flip_genotype($chip_gt);
						}
					
						my $comparison_result = "Unknown";
					
						if($chip_gt eq $ref_gt)
						{
							$stats{'num_chip_was_reference'}++;
						
							if(uc($cons_gt) eq $ref_gt)
							{
								$stats{'num_ref_was_ref'}++;
								$comparison_result = "RefMatch";
							}
							elsif(is_heterozygous($cons_gt))
							{
								$stats{'num_ref_was_het'}++;
								$comparison_result = "RefWasHet";
							}
							else
							{
								$stats{'num_ref_was_hom'}++;
								$comparison_result = "RefWasHom";
							}
						
						}
						elsif($chip_gt ne $ref_gt)
						{
							$stats{'num_with_variant'}++;
													
							if(is_homozygous($chip_gt))
							{
								$stats{'rare_hom_total'}++;
							}
						
							if($chip_gt eq $cons_gt)
							{
								$stats{'num_variant_match'}++;
								if(is_homozygous($chip_gt))
								{
									$stats{'rare_hom_match'}++;
								}
								
								$comparison_result = "VarMatch";
	
							}
							elsif(is_homozygous($chip_gt) && is_heterozygous($cons_gt))
							{
								$stats{'hom_was_het'}++;
								$comparison_result = "HomWasHet";
							}
							elsif(is_heterozygous($chip_gt) && is_homozygous($cons_gt))
							{
								$stats{'het_was_hom'}++;
								$comparison_result = "HetWasHom";
							}
							elsif(is_heterozygous($chip_gt) && is_heterozygous($chip_gt))
							{
								$stats{'het_was_diff_het'}++;
								$comparison_result = "HetMismatch";
							}
							else
							{
								warn "Uncounted comparison: Chip=$chip_gt but Seq=$cons_gt\n";
							}
							

							
							
						}
					
						if($self->verbose)
						{
							$verbose_output .= "$key\t$chip_gt\t$comparison_result\t$cons_gt\t$line\n" if($self->output_file);
							print "$key\t$chip_gt\t$comparison_result\t$cons_gt\t$line\n";
						}						
						
					}
				}
			
			}

		}
		

		
	}
	
	close($input);

	## Set zero values ##
	
	$stats{'num_ref_was_ref'} = 0 if(!$stats{'num_ref_was_ref'});
	$stats{'num_chip_was_reference'} = 0 if(!$stats{'num_chip_was_reference'});

	## Calculate pct ##
	
	$stats{'pct_overall_match'} = "0.00";
	if($stats{'num_with_variant'} || $stats{'num_chip_was_reference'})
	{
		$stats{'pct_overall_match'} = ($stats{'num_variant_match'} + $stats{'num_ref_was_ref'}) / ($stats{'num_chip_was_reference'} + $stats{'num_with_variant'}) * 100;
		$stats{'pct_overall_match'} = sprintf("%.3f", $stats{'pct_overall_match'});
	}

	$stats{'pct_variant_match'} = "0.00";
	if($stats{'num_with_variant'})
	{
		$stats{'pct_variant_match'} = $stats{'num_variant_match'} / $stats{'num_with_variant'} * 100;
		$stats{'pct_variant_match'} = sprintf("%.3f", $stats{'pct_variant_match'});
	}

	$stats{'pct_hom_match'} = "0.00";
	if($stats{'rare_hom_total'})
	{
		$stats{'pct_hom_match'} = $stats{'rare_hom_match'} / $stats{'rare_hom_total'} * 100;
		$stats{'pct_hom_match'} = sprintf("%.3f", $stats{'pct_hom_match'});
	}

	if($self->verbose)
	{
		print $stats{'num_snps'} . " SNPs parsed from variants file\n";
		print $stats{'num_with_genotype'} . " had genotype calls from the SNP array\n";
		print $stats{'num_min_depth'} . " met minimum depth of >= $min_depth_hom/$min_depth_het\n";
		print $stats{'num_chip_was_reference'} . " were called Reference on chip\n";
		print $stats{'num_ref_was_ref'} . " reference were called reference\n";
		print $stats{'num_ref_was_het'} . " reference were called heterozygous\n";
		print $stats{'num_ref_was_hom'} . " reference were called homozygous\n";
		print $stats{'num_with_variant'} . " had informative genotype calls\n";
		print $stats{'num_variant_match'} . " had matching calls from sequencing\n";
		print $stats{'hom_was_het'} . " homozygotes from array were called heterozygous\n";
		print $stats{'het_was_hom'} . " heterozygotes from array were called homozygous\n";
		print $stats{'het_was_diff_het'} . " heterozygotes from array were different heterozygote\n";
		print $stats{'pct_variant_match'} . "% concordance at variant sites\n";
		print $stats{'pct_hom_match'} . "% concordance at rare-homozygous sites\n";
		print $stats{'pct_overall_match'} . "% overall concordance match\n";
	}
	else
	{
		print "Sample\tSNPsCalled\tWithGenotype\tMetMinDepth\tReference\tRefMatch\tRefWasHet\tRefWasHom\tVariant\tVarMatch\tHomWasHet\tHetWasHom\tVarMismatch\tVarConcord\tRareHomConcord\tOverallConcord\n";
		print "$sample_name\t";
		print $stats{'num_snps'} . "\t";
		print $stats{'num_with_genotype'} . "\t";
		print $stats{'num_min_depth'} . "\t";
		print $stats{'num_chip_was_reference'} . "\t";
		print $stats{'num_ref_was_ref'} . "\t";
		print $stats{'num_ref_was_het'} . "\t";
		print $stats{'num_ref_was_hom'} . "\t";
		print $stats{'num_with_variant'} . "\t";
		print $stats{'num_variant_match'} . "\t";
		print $stats{'hom_was_het'} . "\t";
		print $stats{'het_was_hom'} . "\t";
		print $stats{'het_was_diff_het'} . "\t";
		print $stats{'pct_variant_match'} . "%\t";
		print $stats{'pct_hom_match'} . "%\t";		
		print $stats{'pct_overall_match'} . "%\n";
	}

	if($self->output_file)
	{
		print OUTFILE "Sample\tSNPsCalled\tWithGenotype\tMetMinDepth\tReference\tRefMatch\tRefWasHet\tRefWasHom\tVariant\tVarMatch\tHomWasHet\tHetWasHom\tVarMismatch\tVarConcord\tRareHomConcord\tOverallConcord\n";
		print OUTFILE "$sample_name\t";
		print OUTFILE $stats{'num_snps'} . "\t";
		print OUTFILE $stats{'num_with_genotype'} . "\t";
		print OUTFILE $stats{'num_min_depth'} . "\t";
		print OUTFILE $stats{'num_chip_was_reference'} . "\t";
		print OUTFILE $stats{'num_ref_was_ref'} . "\t";
		print OUTFILE $stats{'num_ref_was_het'} . "\t";
		print OUTFILE $stats{'num_ref_was_hom'} . "\t";
		print OUTFILE $stats{'num_with_variant'} . "\t";
		print OUTFILE $stats{'num_variant_match'} . "\t";
		print OUTFILE $stats{'hom_was_het'} . "\t";
		print OUTFILE $stats{'het_was_hom'} . "\t";
		print OUTFILE $stats{'het_was_diff_het'} . "\t";
		print OUTFILE $stats{'pct_variant_match'} . "%\t";
		print OUTFILE $stats{'pct_hom_match'} . "%\t";		
		print OUTFILE $stats{'pct_overall_match'} . "%\n";
		
		print OUTFILE "\nVERBOSE OUTPUT:\n$verbose_output\n";
	}

	return 1;                               # exits 0 for true, exits 1 for false (retval/exit code mapping is overridable)
}


################################################################################################
# Load Genotypes
#
################################################################################################

sub load_genotypes
{                               # replace with real execution logic.
	my $genotype_file = shift(@_);
	my %genotypes = ();
	
	my $input = new FileHandle ($genotype_file);
	my $lineCounter = 0;
	my $gtCounter = 0;

	while (<$input>)
	{
		chomp;
		my $line = $_;
		$lineCounter++;

		(my $chrom, my $position, my $genotype) = split(/\t/, $line);

		my $key = "$chrom\t$position";
		
		if($genotype && $genotype ne "--")
		{
			$genotypes{$key} = $genotype;
			$gtCounter++;
		}
	}
	close($input);

#	print "$gtCounter genotypes loaded\n";
	
	return(%genotypes);                               # exits 0 for true, exits 1 for false (retval/exit code mapping is overridable)
}


################################################################################################
# Sorting
#
################################################################################################


sub byBamOrder
{
	my ($chrom_a, $pos_a) = split(/\t/, $a);
	my ($chrom_b, $pos_b) = split(/\t/, $b);
	
	$chrom_a =~ s/X/9\.1/;
	$chrom_a =~ s/Y/9\.2/;
	$chrom_a =~ s/MT/25/;
	$chrom_a =~ s/M/25/;
	$chrom_a =~ s/NT/99/;
	$chrom_a =~ s/[^0-9\.]//g;

	$chrom_b =~ s/X/9\.1/;
	$chrom_b =~ s/Y/9\.2/;
	$chrom_b =~ s/MT/25/;
	$chrom_b =~ s/M/25/;
	$chrom_b =~ s/NT/99/;
	$chrom_b =~ s/[^0-9\.]//g;

	$chrom_a <=> $chrom_b
	or
	$pos_a <=> $pos_b;
}


################################################################################################
# Load Genotypes
#
################################################################################################

sub is_heterozygous
{
	my $gt = shift(@_);
	(my $a1, my $a2) = split(//, $gt);
	return(1) if($a1 ne $a2);
	return(0);
}



################################################################################################
# Load Genotypes
#
################################################################################################

sub is_homozygous
{
	my $gt = shift(@_);
	(my $a1, my $a2) = split(//, $gt);
	return(1) if($a1 eq $a2);
	return(0);
}



################################################################################################
# Load Genotypes
#
################################################################################################

sub flip_genotype
{
	my $gt = shift(@_);
	(my $a1, my $a2) = split(//, $gt);

	if($a1 eq "A")
	{
		$a1 = "T";
	}
	elsif($a1 eq "C")
	{
		$a1 = "G";
	}
	elsif($a1 eq "G")
	{
		$a1 = "C";
	}	
	elsif($a1 eq "T")
	{
		$a1 = "A";		
	}

	if($a2 eq "A")
	{
		$a2 = "T";
	}
	elsif($a2 eq "C")
	{
		$a2 = "G";
	}
	elsif($a2 eq "G")
	{
		$a2 = "C";
	}	
	elsif($a2 eq "T")
	{
		$a2 = "A";		
	}
	
	$gt = $a1 . $a2;
	$gt = sort_genotype($gt);
	return($gt);
}

################################################################################################
# Load Genotypes
#
################################################################################################

sub sort_genotype
{
	my $gt = shift(@_);
	(my $a1, my $a2) = split(//, $gt);

	my @unsorted = ($a1, $a2);
	my @sorted = sort @unsorted;
	$a1 = $sorted[0];
	$a2 = $sorted[1];
	return($a1 . $a2);
}



sub code_to_genotype
{
	my $code = shift(@_);
	
	return("AA") if($code eq "A");
	return("CC") if($code eq "C");
	return("GG") if($code eq "G");
	return("TT") if($code eq "T");

	return("AC") if($code eq "M");
	return("AG") if($code eq "R");
	return("AT") if($code eq "W");
	return("CG") if($code eq "S");
	return("CT") if($code eq "Y");
	return("GT") if($code eq "K");

#	warn "Unrecognized ambiguity code $code!\n";

	return("NN");	
}



sub commify
{
	local($_) = shift;
	1 while s/^(-?\d+)(\d{3})/$1,$2/;
	return $_;
}


1;

