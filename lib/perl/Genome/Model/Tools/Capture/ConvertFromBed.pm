
package Genome::Model::Tools::Capture::ConvertFromBed;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# ConvertFromBedForAnnotation - Merge glfSomatic/Varscan somatic calls in a file that can be converted to MAF format
#					
#	AUTHOR:		Dan Koboldt (dkoboldt@watson.wustl.edu)
#
#	CREATED:	10/23/2009 by D.K.
#	MODIFIED:	10/23/2009 by D.K.
#
#	NOTES:	
#			
#####################################################################################################################################

use strict;
use warnings;
use FileHandle;
use Genome;                                 # using the namespace authorizes Class::Autouse to lazy-load modules under it

class Genome::Model::Tools::Capture::ConvertFromBed {
	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		variant_file	=> { is => 'Text', doc => "Variants in BED format", is_optional => 0, is_input => 1 },
		output_file     => { is => 'Text', doc => "Output file to receive annotation-formatted lines", is_optional => 0, is_input => 1, is_output => 1 },
	],
};

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
    "Reformats from BED to annotation format"                 
}

sub help_synopsis {
    return <<EOS
This command reformats from BED to annotation format
EXAMPLE:	gmt capture convert-from-bed --variant-file [file] --output-file [file]
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
	my $output_file = $self->output_file;
	
	## Open outfile ##
	
	open(OUTFILE, ">$output_file") or die "Can't open outfile: $!\n";
	
	## Parse the indels ##

	my $input = new FileHandle ($variant_file);
	my $lineCounter = 0;

	my @formatted = ();
	my $formatCounter = 0;
	
	while (<$input>)
	{
		chomp;
		my $line = $_;
		$lineCounter++;		

		my @lineContents = split(/\t/, $line);

		if(!(lc($lineContents[0]) =~ "chrom" || lc($lineContents[0]) =~ "ref_name"))
		{
			my $chrom = $lineContents[0];
			$chrom = fix_chrom($chrom);
			my $chr_start = $lineContents[1];
			my $chr_stop = $lineContents[2];
			my ($allele1, $allele2) = split(/\//, $lineContents[3]);

			my $restColumn = 4;

			if($chrom && $chr_start && $chr_stop)
			{
#				$allele2 = iupac_to_base($allele1, $allele2);
	
				## If we have other information on line, output it ##
				my $numContents = @lineContents;
				my $rest_of_line = "";
				if($restColumn && $restColumn > 0 && $restColumn < $numContents)
				{
					for(my $colCounter = $restColumn; $colCounter < $numContents; $colCounter++)
					{
						$rest_of_line .= "\t" if($colCounter > $restColumn);
						$rest_of_line .= $lineContents[$colCounter];
					}
	
				}
	
				$chr_start++ if(($chr_stop - $chr_start) == 1);
	
				$formatted[$formatCounter] = "$chrom\t$chr_start\t$chr_stop\t$allele1\t$allele2";
				$formatted[$formatCounter] .= "\t$rest_of_line" if($rest_of_line);
				$formatCounter++;
			}
		}
	}

	close($input);
	
	## Sort the formatted indels by chr pos ##

	@formatted = sort byChrPos @formatted;
	
	foreach my $snv (@formatted)
	{
		print OUTFILE "$snv\n";
	}
	
	
	close(OUTFILE);
}


#############################################################
# ParseBlocks - takes input file and parses it
#
#############################################################

sub fix_chrom
{
	my $chrom = shift(@_);
	$chrom =~ s/chr// if(substr($chrom, 0, 3) eq "chr");
	$chrom =~ s/[^0-9XYMNT\_random]//g;	

	return($chrom);
}


#############################################################
# ParseBlocks - takes input file and parses it
#
#############################################################

sub iupac_to_base
{
	(my $allele1, my $allele2) = @_;
	
	return($allele2) if($allele2 eq "A" || $allele2 eq "C" || $allele2 eq "G" || $allele2 eq "T");
	
	if($allele2 eq "M")
	{
		return("C") if($allele1 eq "A");
		return("A") if($allele1 eq "C");
	}
	elsif($allele2 eq "R")
	{
		return("G") if($allele1 eq "A");
		return("A") if($allele1 eq "G");		
	}
	elsif($allele2 eq "W")
	{
		return("T") if($allele1 eq "A");
		return("A") if($allele1 eq "T");		
	}
	elsif($allele2 eq "S")
	{
		return("C") if($allele1 eq "G");
		return("G") if($allele1 eq "C");		
	}
	elsif($allele2 eq "Y")
	{
		return("C") if($allele1 eq "T");
		return("T") if($allele1 eq "C");		
	}
	elsif($allele2 eq "K")
	{
		return("G") if($allele1 eq "T");
		return("T") if($allele1 eq "G");				
	}	
	
	return($allele2);
}

sub byChrPos
{
    (my $chrom_a, my $pos_a) = split(/\t/, $a);
    (my $chrom_b, my $pos_b) = split(/\t/, $b);

	$chrom_a =~ s/X/23/;
	$chrom_a =~ s/Y/24/;
	$chrom_a =~ s/MT/25/;
	$chrom_a =~ s/M/25/;
	$chrom_a =~ s/[^0-9]//g;

	$chrom_b =~ s/X/23/;
	$chrom_b =~ s/Y/24/;
	$chrom_b =~ s/MT/25/;
	$chrom_b =~ s/M/25/;
	$chrom_b =~ s/[^0-9]//g;

    $chrom_a <=> $chrom_b
    or
    $pos_a <=> $pos_b;
    
#    $chrom_a = 23 if($chrom_a =~ 'X');
#    $chrom_a = 24 if($chrom_a =~ 'Y');
    
}


1;

