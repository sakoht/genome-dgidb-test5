package Genome::Model::Tools::Somatic::StrandFilter;

use strict;
use warnings;

use Genome;
use Command;
use IO::File;
use Readonly;
use Genome::Info::IUB;

class Genome::Model::Tools::Somatic::StrandFilter {
    is => 'Command',
    has => [
       'variant_file' => {
           type => 'String',
           is_input => 1,
           doc => 'List of variant positions in annotation format',
       },
       'output_file' => {
           type => 'String',
           is_input => 1,
           is_output => 1,
           doc => 'File name in which to write output',
       },
       'filtered_file' => {
           type => 'String',
           is_input => 1,
           is_output => 1,
           doc => 'File name in which to write variants that were filtered',
       },       
       'tumor_bam_file' => {
            type => 'String',
            doc => 'Tumor bam file in which to examine reads',
            is_input => 1,
       },
       'min_strandedness' => {
            type => 'String',
            default => '0.10',
            is_optional => 1,
            is_input => 1,
            doc => 'Minimum representation of variant allele on each strand',
       },
       'min_read_pos' => {
            type => 'String',
            default => '0.05',
            is_optional => 1,
            is_input => 1,
            doc => 'Minimum average relative distance from start/end of read',
       },
       prepend_chr => {
           is => 'Boolean',
           default => '0',
           is_optional => 1,
           is_input => 1,
           doc => 'prepend the string "chr" to chromosome names. This is primarily used for external/imported bam files.',
       },
       # Make workflow choose 64 bit blades
       lsf_resource => {
            is_param => 1,
            default_value => 'rusage[mem=4000] select[type==LINUX64] span[hosts=1]',
       },
       lsf_queue => {
            is_param => 1,
            default_value => 'long',
       },
       skip => {
           is => 'Boolean',
           default => '0',
           is_input => 1,
           is_optional => 1,
           doc => "If set to true... this will do nothing! Fairly useless, except this is necessary for workflow.",
       },
        skip_if_output_present => {
            is => 'Boolean',
            is_optional => 1,
            is_input => 1,
            default => 0,
            doc => 'enable this flag to shortcut through annotation if the output_file is already present. Useful for pipelines.',
        },
    ]
};

sub help_brief {
    return "This module uses strandedness and read position to further filter somatic variants";
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
    gmt somatic strand-filter --variant-file somatic.snvs --tumor-bam tumor.bam --output-file somatic.snvs.strandfilter 
EOS
}

sub help_detail {                           
    return <<EOS 
This module uses strandedness and read position to further filter somatic variants
EOS
}

sub execute {
    my $self = shift;
    $DB::single=1;

    if ($self->skip) {
        $self->status_message("Skipping execution: Skip flag set");
        return 1;
    }
    
    if (($self->skip_if_output_present)&&(-s $self->output_file)) {
        $self->status_message("Skipping execution: Output is already present and skip_if_output_present is set to true");
        return 1;
    }

    #test architecture to make sure we can run read count program
    unless (`uname -a` =~ /x86_64/) {
       $self->error_message("Must run on a 64 bit machine");
       die;
    }

    #check on BAM file
    unless(-e $self->tumor_bam_file) {
        $self->error_message("Tumor bam file: " . $self->tumor_bam_file . " does not exist");
        die;
    }

    unless(-e $self->tumor_bam_file . ".bai") {
        $self->error_message("Tumor bam must be indexed");
        die;
    }


    ## Determine the strandedness and read position thresholds ##
    
    my $min_read_pos = $self->min_read_pos;
    my $max_read_pos = 1 - $min_read_pos;
    
    my $min_strandedness = $self->min_strandedness;
    my $max_strandedness = 1 - $min_strandedness;

    ## Reset counters ##
    
    my $num_variants = my $num_fail_strand = my $num_fail_pos = my $num_pass_filter = 0;


    ## Open the output file ##
    
    my $ofh = IO::File->new($self->output_file, "w");
    unless($ofh) {
        $self->error_message("Unable to open " . $self->output_file . " for writing. $!");
        die;
    }

    ## Open the filtered output file ##
    
    my $ffh = IO::File->new($self->filtered_file, "w") if($self->filtered_file);


    ## Open the variants file ##

    my $input = new FileHandle ($self->variant_file);

    unless($input) {
        $self->error_message("Unable to open " . $self->variant_file . ". $!");
        die;
    }

    ## Parse the variants file ##

    my $lineCounter = 0;
    
    while (<$input>)
    {
            chomp;
            my $line = $_;
            $lineCounter++;

            $num_variants++;
            
#            if($lineCounter <= 10)
 #           {
                (my $chrom, my $chr_start, my $chr_stop, my $ref, my $var) = split(/\t/, $line);
                
                my $query_string = "";
                
                if($self->prepend_chr)
                {
                    $query_string = "chr" . $chrom . ":" . $chr_start . "-" . $chr_stop;
                }
                else
                {
                    $query_string = $chrom . ":" . $chr_start . "-" . $chr_stop;
                }

                ## if the variant allele is an IUPAC code, convert it: ##
                
                if(!($var =~ /[ACGT]/))
                {
                    $var = iupac_to_base($ref, $var);
                }
    
                if($var =~ /[ACGT]/)
                {
                    ## Run Readcounts ##
                    my $cmd = readcount_program() . " -b 15 " . $self->tumor_bam_file . " $query_string";
                    my $readcounts = `$cmd`;
                    chomp($readcounts) if($readcounts);
        
                    ## Parse the results for each allele ##
        
                    my $ref_result = read_counts_by_allele($readcounts, $ref);
                    my $var_result = read_counts_by_allele($readcounts, $var);
                    
                    if($ref_result && $var_result)
                    {
                            ## Calculate percent-fwd-strand ##
                            (my $ref_count, my $ref_map, my $ref_base, my $ref_semq, my $ref_plus, my $ref_minus, my $ref_pos, my $ref_subs) = split(/\t/, $ref_result);
                            (my $var_count, my $var_map, my $var_base, my $var_semq, my $var_plus, my $var_minus, my $var_pos, my $var_subs) = split(/\t/, $var_result);
                            			    
                            if($var_count && ($var_plus + $var_minus))
                            {
    #                            my $ref_pct_plus = $ref_plus / ($ref_plus + $ref_minus);
     #                           $ref_pct_plus = sprintf("%.2f", $ref_pct_plus);
            
                               my $var_pct_plus = $var_plus / ($var_plus + $var_minus);
                                $var_pct_plus = sprintf("%.2f", $var_pct_plus);
            
                                ## Count the failures ##
                                
                                $num_fail_pos++ if(!($var_pos >= $min_read_pos && $var_pos <= $max_read_pos));
                                $num_fail_strand++ if(!($var_pct_plus >= $min_strandedness && $var_pct_plus <= $max_strandedness));
            
                                if($var_pct_plus >= $min_strandedness && $var_pct_plus <= $max_strandedness)
                                {
                                    if($var_pos >= $min_read_pos && $var_pos <= $max_read_pos)
                                    {
                                        print $ofh "$line\n";
                                        print "$chrom\t$chr_start\t$chr_stop\t$ref\t$var\tPASS\n";
                                        $num_pass_filter++;
                                    }
                                    else
                                    {
					print $ffh "$line\treadpos=$var_pos\n"if ($self->filtered_file);
                                        print "$chrom\t$chr_start\t$chr_stop\t$ref\t$var\tFAIL read pos=$var_pos\n";
                                    }
                                }
                                else
                                {
				    print $ffh "$line\tstrandedness=$var_pct_plus\n"if ($self->filtered_file);
                                    print "$chrom\t$chr_start\t$chr_stop\t$ref\t$var\tFAIL strandedness=$var_pct_plus\n";                            
                                }
                            }
                            else
                            {
				print $ffh "$line\tno_reads\n" if($self->filtered_file);
                                print "$chrom\t$chr_start\t$chr_stop\t$ref\t$var\tFAIL no reads in $var_result\n";        
                            }
                    }
                    else
                    {
                        $self->error_message("Unable to get read counts for $ref/$var from $readcounts using $cmd: ref was $ref_result var was $var_result");
                        die;                
                    }
                }
#            }
    }
    
    close($input);

    print "$num_variants variants\n";
    print "$num_fail_strand had strandedness < $min_strandedness\n";
    print "$num_fail_pos had read position < $min_read_pos\n";
    print "$num_pass_filter passed the strand filter\n";

    return 1;
}

sub readcount_program {
    return "/gscuser/dlarson/src/bamsey/readcount/trunk/bam-readcount -f /gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/all_sequences.fa";
}




#############################################################
# ParseFile - takes input file and parses it
#
#############################################################

sub read_counts_by_allele
{
	(my $line, my $allele) = @_;
	
	my @lineContents = split(/\t/, $line);
	my $numContents = @lineContents;
	
	for(my $colCounter = 5; $colCounter < $numContents; $colCounter++)
	{
		my $this_allele = $lineContents[$colCounter];
		my @alleleContents = split(/\:/, $this_allele);
		if($alleleContents[0] eq $allele)
		{
			my $numAlleleContents = @alleleContents;
			
			return("") if($numAlleleContents < 8);
			
			my $return_string = "";
			my $return_sum = 0;
			for(my $printCounter = 1; $printCounter < $numAlleleContents; $printCounter++)
			{
				$return_sum += $alleleContents[$printCounter];
				$return_string .= "\t" if($return_string);
				$return_string .= $alleleContents[$printCounter];
			}
			
                        return($return_string);
                        
#			if($return_sum)
#			{
#				return($return_string);
#			}
#			else
#			{
#				return("");
#			}
		}
	}
	
	return("");
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



1;
