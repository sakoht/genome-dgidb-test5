package Genome::Model::Tools::Validation::CombineCounts;

use strict;
use warnings;

use Genome;
use Genome::Info::IUB;
use IO::File;
use POSIX;
use Genome::Statistics; #for fisher's exact test

class Genome::Model::Tools::Validation::CombineCounts {
    is => 'Command',
    has => [
    count_files => {
        type => 'String',
        is_optional => 0,
        doc => 'Files of counts generated by gmt validation count-contigs. Comma separated values',
        default => '',
    },
    file_labels => {
        type => 'String',
        is_optional => 1,
        doc => 'Labels to assign the files passed in --count-files. Should be comma separated ie tumor,normal,relapse',
    },
    minimum_coverage => {
        type => 'Integer',
        is_optional => 0,
        default => 30,
        doc => "minimum coverage to make a call. sites without this minimum will be called as NC (no coverage)"
    },
    maximum_contig_read_exclusion_rate => {
        type => 'Float',
        is_optional => 0,
        default => 0.25,
        doc => "Maximum fraction of covering reads excluded due to clipping or paralog content to make a call",
    },
    minimum_variant_supporting_reads => {
        type => 'Integer',
        is_optional => 0,
        default => 2,
        doc => "Number of variant reads required to report as a variant",
    },
    minimum_variant_frequency => {
        type => 'Float',
        is_optional => 0,
        default => 0.08,
        doc => "Minimum variant frequency to consider a site as a variant",
    },
    normal_purity => {
        type => 'Float',
        is_optional => 0,
        default => 1,
        doc => "Purity of the normal sample. This dynamically adjusts the minimum allele frequency for the normal sample to be considered variant",
    },
    minimum_homozygous_frequency => {
        type => 'Float',
        is_optional => 0,
        default => 0.7,
        doc => "Minimum frequency to call a site as homozygous variant",
    },
    maximum_p_value => {
        type => 'Float',
        is_optional => 0,
        default => 0.001,
        doc => "The maximum p-value to report a site as somatic or germline",
    },
    somatic_comparisons => {
        type => 'String',
        is_optional => 0,
        doc => "comma or big-comma separated string of pairs to calculate somatic p-values on e.g. normal,tumor or normal => tumor compares tumor to normal",
    },
    #some sort of pairwise comparison descriptor
    output_file => {
        type => 'String',
        is_optional => 0,
        doc => 'output file for combined readcounts + somatic status calling',
    },

    #Genome::Statistics::calculate_p_value($normal_read_support, $normal_read_sw_support, $tumor_read_support, $tumor_read_sw_support);

    ]
};

sub execute {
    my $self=shift;
    $DB::single = 1;
    my @files = split /\s*,\s*/, $self->count_files;
    my @orig_labels = split /\s*,\s*/, $self->file_labels if $self->file_labels;
    my @labels = @orig_labels;  #set this up so we can pop off labels during file parsing

    #open output file for writing
    my $outfh = new IO::File $self->output_file,"w";

    #prepare for VarScan type scoring
    my %comparisons;
    my @comparison_specification = split /\s*,\s*|\s*=>\s*/, $self->somatic_comparisons;
    if(@comparison_specification % 2) {
        $self->error_message("Number of samples in comparison string is not a multiple of two. Mismatching pairs?");
        return;
    }
    my %counts; #counts of the contigs and their variants

    #info on the count headers/fields
    my @contig_specific_fields = qw( contig_id contigs_overlapping);
    my @bam_specific_fields = qw( ref_clipped_reads_excluded ref_paralog_reads_excluded total_reads_crossing_ref_pos total_q1_reads_crossing_ref_pos total_q1_reads_spanning_ref_pos contig_clipped_reads_excluded contig_paralog_reads_excluded total_reads_crossing_contig_pos total_q1_reads_crossing_contig_pos total_q1_reads_spanning_contig_pos );
    my @sample_calculated_fields = qw( coverage frequency excluded_freq clip_freq paralog_freq);
    
    for my $file (@files) {
        my $fh = IO::File->new($file, "r");
        unless($fh) {
            $self->error_message("Couldn't open $file: $!"); 
            return;
        }

        my $label;
        if(@labels) {
            $label = shift @labels; #grab the label for this file
        }
        else {
            $label = $file;
        }


        #parse in the counts
        while(my $line = $fh->getline) {
            next if $line =~ /contig_id/;   #skip the header
            chomp $line;

            my @fields = split /\t/, $line;

            my ($contig_id, $overlap) = @fields;

            my $count_entry;
            if(exists($counts{$contig_id})) {
                unless($counts{$contig_id}{contigs_overlapping} == $overlap) {
                    #mismatching overlap notation, probably not the same set of contigs
                    $self->error_message("Mismatching overlap number between contigs, did you use the same contigs for your two files?");
                    return;
                }
                $count_entry = $counts{$contig_id};
            }
            else {
                $counts{$contig_id}{contigs_overlapping} = $overlap;
                $count_entry = $counts{$contig_id};
            }

            #check that we don't have a duplicate label
            if(exists($count_entry->{$label})) {
                $self->error_message("Duplicate data or duplicate label for $contig_id with label $label");
                return;
            }

            @{$count_entry->{$label}}{@bam_specific_fields} = @fields[2..$#fields]; #store the info
        }
    }

    #now we're all done, lets spit this stuff out. 

    #spit out a header, cause that's a good idea

    my @labeled_calculated_header;
    print $outfh join("\t", @contig_specific_fields); 
    foreach my $label (@orig_labels) {
        my @labeled_fields =  map { "${label}_$_" } @bam_specific_fields;
        print $outfh "\t", join("\t", @labeled_fields);

        push @labeled_calculated_header, map { "${label}_$_" } @sample_calculated_fields;
    }

    print $outfh "\t",join("\t", @labeled_calculated_header);
    print $outfh "\t", qw( contig_exclusion_freq );
    
    for(my $i = 0; $i < @comparison_specification; $i += 2) {
        my ($control, $experimental) = @comparison_specification[$i,$i+1];
        my $comparison_label = "${experimental}_vs_${control}_";
        print $outfh "\t", join("\t",map { $comparison_label . $_ } qw{ variant_p_value somatic_p_value status });
    }

    print $outfh "\n";

    #now print the data
    foreach my $contig_id (sort keys %counts) {
        print $outfh join("\t",$contig_id, $counts{$contig_id}{contigs_overlapping});
        my %calculated_values;
        my $total_contig_reads = 0;
        my $total_excluded_contig_reads = 0;
        foreach my $label (@orig_labels) {
            my @fields = @{$counts{$contig_id}{$label}}{@bam_specific_fields};
            print $outfh "\t",join("\t",@fields);
            
            #calculate the per sample metrics
            my $coverage = $counts{$contig_id}{$label}->{total_q1_reads_spanning_ref_pos} + $counts{$contig_id}{$label}->{total_q1_reads_spanning_contig_pos};
            my $frequency = $coverage ? $counts{$contig_id}{$label}->{total_q1_reads_spanning_contig_pos} / ($counts{$contig_id}{$label}->{total_q1_reads_spanning_contig_pos} + $counts{$contig_id}{$label}->{total_q1_reads_spanning_ref_pos}) : '-';
            my $total_reads = ($counts{$contig_id}{$label}->{contig_clipped_reads_excluded} + $counts{$contig_id}{$label}->{contig_paralog_reads_excluded} + $counts{$contig_id}{$label}->{total_reads_crossing_contig_pos});
            my $excluded_contig_freq = $total_reads ? ($counts{$contig_id}{$label}->{contig_clipped_reads_excluded} + $counts{$contig_id}{$label}->{contig_paralog_reads_excluded}) / $total_reads : '-';
            my $clip_freq = $total_reads ? $counts{$contig_id}{$label}->{contig_clipped_reads_excluded} / $total_reads : '-';
            my $paralog_freq = $total_reads ? $counts{$contig_id}{$label}->{contig_paralog_reads_excluded} / $total_reads : '-';
            @{$calculated_values{$label}}{@sample_calculated_fields} = ($coverage, $frequency, $excluded_contig_freq, $clip_freq, $paralog_freq);

            $total_contig_reads += $total_reads;
            $total_excluded_contig_reads += $counts{$contig_id}{$label}->{contig_clipped_reads_excluded} + $counts{$contig_id}{$label}->{contig_paralog_reads_excluded};

        }
        #the following line just uses array slices to maintain the ordering of fields and labels (samples)
        #It is too beautiful as is. Sorry.
        print $outfh "\t",join("\t", map { @$_{@sample_calculated_fields} } @calculated_values{@orig_labels});
        my $exclusion_rate = $total_contig_reads ? $total_excluded_contig_reads / $total_contig_reads : '-';
        print $outfh "\t", $exclusion_rate;

        #do varscan comparisons
        for(my $i = 0; $i < @comparison_specification; $i += 2) {
            my ($control, $experimental) = @comparison_specification[$i,$i+1];
            my %call = $self->varscan_call($counts{$contig_id}{$control}->{total_q1_reads_spanning_ref_pos}, $counts{$contig_id}{$control}->{total_q1_reads_spanning_contig_pos}, $counts{$contig_id}{$experimental}->{total_q1_reads_spanning_ref_pos},$counts{$contig_id}{$experimental}->{total_q1_reads_spanning_contig_pos});
            #here change the status based on the exclusion criterion
            if($exclusion_rate ne '-' && $exclusion_rate > $self->maximum_contig_read_exclusion_rate) {
                $call{status} = "ExclusionFiltered";
            }
            print $outfh "\t", join("\t", @call{ qw( variant_p_value somatic_p_value status ) });
        }
        print $outfh "\n";
    }
    return 1;
}


1;

sub help_brief {
    "Scans a file of contigs, parses information about where they need to be counted and then spits out info."
}

sub help_detail {
    <<'HELP';
HELP
}


#this code generally borrowed from GMT::Gatk::VarscanIndel.pm
#some corrections, re-working
sub varscan_call {
    my ($self, $normal_ref_reads, $normal_var_reads, $tumor_ref_reads, $tumor_var_reads) = @_;

    #we don't yet have alleles included in the results, and we're not sure how good they really are, but proceed anyways.
    my $normal_coverage = $normal_ref_reads + $normal_var_reads;
    my $tumor_coverage = $tumor_ref_reads + $tumor_var_reads;

    unless($normal_coverage && $tumor_coverage && $normal_coverage >= $self->minimum_coverage && $tumor_coverage >= $self->minimum_coverage) {
        return (genotype => [], variant_p_value => '-', somatic_p_value => '-', status => 'NC',);
    }

    my $normal_freq = $normal_var_reads / $normal_coverage;
    my $tumor_freq = $tumor_var_reads / $tumor_coverage;

    my ($normal_genotype,$tumor_genotype);

    #Call the genotype in normal
    if($normal_var_reads >= $self->minimum_variant_supporting_reads && $normal_freq >= ($self->minimum_variant_frequency / $self->normal_purity)) {
        if($normal_freq >= ($self->minimum_homozygous_frequency / $self->normal_purity)) {
            $normal_genotype = "I/I";
        }
        else {
            $normal_genotype = "*/I";
        }
    }
    else {
        $normal_genotype = "*/*";
    }

    #call the genotype in the tumor
    if($tumor_var_reads >= $self->minimum_variant_supporting_reads && $tumor_freq >= $self->minimum_variant_frequency)
    {
        if($tumor_freq >= $self->minimum_homozygous_frequency) {
            $tumor_genotype = "I/I";
        }
        else {
            $tumor_genotype = "*/I";
        }
    }
    else {
        $tumor_genotype = "*/*";
    }

    ## Calculate P-value
    my $variant_p_value = Genome::Statistics::calculate_p_value(($normal_coverage + $tumor_coverage), 0, ($normal_ref_reads + $tumor_ref_reads), ($normal_var_reads + $tumor_var_reads));
    if($variant_p_value < 0.001) {
        $variant_p_value = sprintf("%.3e", $variant_p_value);
    }
    else {
        $variant_p_value = sprintf("%.5f", $variant_p_value);
    }

    my $somatic_p_value = Genome::Statistics::calculate_p_value($normal_ref_reads, $normal_var_reads, $tumor_ref_reads, $tumor_var_reads);
    if($somatic_p_value < 0.001) {
        $somatic_p_value = sprintf("%.3e", $somatic_p_value);
    }
    else {
        $somatic_p_value = sprintf("%.5f", $somatic_p_value);
    }


    ## Determine Somatic Status ##

    my $somatic_status = "";

    if($normal_genotype eq "*/*") {
        if($tumor_genotype ne "*/*" && $somatic_p_value <= $self->maximum_p_value) {
            $somatic_status = "Somatic";
        }
        elsif($variant_p_value <= $self->maximum_p_value) {
            $somatic_status = "Germline";
        }
        elsif($tumor_genotype eq "*/*") {
            $somatic_status = "Reference";
        }
        else {
            $somatic_status = "Unknown";
        }

    }
    elsif($normal_genotype eq "*/I") {
        if(($tumor_genotype eq "I/I" || $tumor_genotype eq "*/*") && $somatic_p_value <= $self->maximum_p_value) {
            $somatic_status = "LOH";
        }
        else {
            $somatic_status = "Germline";
        }
    }
    else {
        ## Normal is homozygous ##
        $somatic_status = "Germline";
    }
    my %call = (    genotype => [ $normal_genotype, $tumor_genotype ],
                    variant_p_value => $variant_p_value,
                    somatic_p_value => $somatic_p_value,
                    status => $somatic_status,
    );
    return %call;
}
