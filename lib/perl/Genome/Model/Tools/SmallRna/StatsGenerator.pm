package Genome::Model::Tools::SmallRna::StatsGenerator;

#based on input from ClusterCoverage(JW) instead of ClusterGenerator(JH)#
#also merged sub-clustering
#Additional parameter added to take in minimum % map score for subclustering 
# FUNCTIONALITY FOR NORMALIZATION USING FLAGSTAT FILES
	#a) added new parameter for taking in flagstat from 17-70 bp bam
	#b) Other flagstat for the respective size-fraction will be intuitively determined


use strict;
use warnings;

use Data::Dumper;
use Statistics::Descriptive;
use Genome;

my $DEFAULT_CUTOFF = '2';

class Genome::Model::Tools::SmallRna::StatsGenerator {
	is        => ['Genome::Model::Tools::SmallRna::Base'],
	has_input => [
		coverage_stats_file => {
			is_output=> 1,
			is  => 'Text',
			doc => 'Input stats file from ClusterCoverage',
		},
  
		bam_file => {
			is  => 'Text',
			doc => 'Input BAM file of alignments',
			is_output=>1
		},
		
		flagstat_17_70_file => {
			is  => 'Text',
			doc => 'Input BAM file of alignments',
			is_output=>1
		},
		output_stats_file => {
			is => 'Text',
			is_output=> 1,
			doc =>'Output STATS file containing statistics for the clusters ',

		},
		output_clusters_file => {
			is => 'Text',
			is_output=> 1,
			doc =>'Output BED file containing coordinates of clusters in BED format (sorted by depth) ',

		},   
	   output_subclusters_file => {
			is        => 'Text',
			is_output => 1,
			doc 	  =>'Output BED file of Subclusters for each cluster in the input BED file',

		},
		output_subcluster_intersect_file => {
			is        => 'Text',
			is_output => 1,
			doc       =>'Output TSV file of Subclusters that mapped with existing clusters',

		},
		
		subcluster_min_mapzero => {
			is        => 'Text',
			is_output => 1,
			doc       =>'Minimum %MapZero Alignments to call subclusters',
			default_value => $DEFAULT_CUTOFF,

		},
	],
};

sub execute {
	my $self     = 	shift;
	my $bamfile  = 	$self->bam_file;
	my $coverage = 	$self->coverage_stats_file;
	#my $clusters = 	$self->input_cluster_number;
	my $output 	 	=  $self->output_stats_file;
	my $cutoff 		= $self ->subcluster_min_mapzero;
	my $sub_output  = $self->output_subclusters_file;
	my $flagstat_17_70 = $self->flagstat_17_70_file;
	my $flagstat_file= $bamfile.'.flagstat';	
	
	
	
	
	### OPENING 17_70 FLAGSTAT FILE AND GETTING STATS###
    	my $data_flagstats_17_70 = Genome::Model::Tools::Sam::Flagstat->parse_file_into_hashref($flagstat_17_70);
        my $flagstat_total_17_70 = $data_flagstats_17_70->{total_reads};
    	my $flagstat_mapped_17_70 = $data_flagstats_17_70->{reads_mapped};

	
	
	### OPENING BIN FLAGSTAT FILE AND GETTING STATS###

    	my $data_flagstats = Genome::Model::Tools::Sam::Flagstat->parse_file_into_hashref($flagstat_file);
        my $flagstat_total = $data_flagstats->{total_reads};
    	my $flagstat_mapped = $data_flagstats->{reads_mapped};
	

	
	
	######OPENING BAM AND GENERATING STATS#######
	
	my $index    =  Bio::DB::Bam->index_open($bamfile);
	
	my	$output_cluster_bed = $self->output_clusters_file;
    my  $output_cluster_fh = Genome::Sys->open_file_for_writing($output_cluster_bed);
    my 	$sub_output_fh = Genome::Sys->open_file_for_writing($sub_output);
    
    ###  SORTING CLUSTERS FROM CLUSTER-COVERAGE STATS FILE AND WRITING ENTRIES TO A NEW "SORTED" FILE##
    
    my ($sorted_temp_fh, $sorted_temp_name) = Genome::Sys->create_temp_file();
    my $cmd = 'sort -nrk 2 '.$coverage.' > '.$sorted_temp_name;
    
    Genome::Sys->shellcmd(
        cmd => $cmd,
        input_files => [$self->coverage_stats_file],
        output_files => [$sorted_temp_name],
        skip_if_output_is_present => 0,
    );
  
    ##OPENING "SORTED" COVERAGE FILE##
    my $coverage_fh = Genome::Sys->open_file_for_reading($sorted_temp_name);
	my $i   = 0;
    
    ### WRITING TO ALIGNMENT STATS FILE####
    my $output_fh = Genome::Sys->open_file_for_writing($output);
	print $output_fh join("\t","Cluster",
		"Chr",
		"Start",
		"Stop",
		"Avg Depth",
		"Zenith Depth",
		"Length of Raw Cluster",
		"Normalization -17_70",
		"Normalization -per bin",
		"% Mismatches",
		"ZeroMM",
		"1MM",
		"2MM",
		"3MM",
		"4MM",
		"% 1st Pos MM ",
		"Avg MapQ",
		"Std Dev Map Q",
		"%Zero MapQ",
		"Avg BaseQ")
		."\n"	;
		
		
	#### CREATE A TEMPORARY BED FILE###
	my ( $bed_temp_fh, $bed_temp_name ) = Genome::Sys->create_temp_file();
		
	#####OPENING BAM FILE AND MATCHING TID TO CHR######
	my %chr_to_id;
    my $bam           = Bio::DB::Bam->open($bamfile); 
	my $header        = $bam->header();                     # TODO : use the name ->tid method
	my $name_arrayref = $header->target_name;

	for ( my $tid = 0 ; $tid < scalar( @{$name_arrayref} ) ; $tid++ )
		{
			my $seq_id = $header->target_name->[$tid];
			$chr_to_id{$seq_id} = $tid;
		}
		
		
	### READ "SORTED" CLUSTER-COVERAGE FILE LINE BY LINE###
		
	 while (my $cov_line = $coverage_fh->getline) 
	 {
		chomp $cov_line;
		if ($cov_line !~ /^name/)
		{
		
		$i++;
		my @cov_arr = split ("\t",$cov_line);
		my $depth = $cov_arr[1]; 
		my $id = $cov_arr[0];
		my $start =0;
		my $stop = 0;
		my $zenith_depth = $cov_arr[5];
		my @line_arr = split ("-", $id);
		my $chrom_start = $line_arr[0];
	    $stop = $line_arr[1];
		
		my @name_arr = split (':', $chrom_start);
		my $chr  = $name_arr[0];
		$start = $name_arr[1];
		
		my $name = 'CLUSTER-'.$i;
		my $cluster_length = ($stop - $start) + 1;
		
		print $output_cluster_fh join("\t",$chr,$start,$stop,$name)."\n";  ### NEW BED FILE OF CLUSTERS - SORTED AND NAMED ###
		
		my %count_of;
		my $first_position_mm = 0;
		my $CountZeroMapQ = 0;

		my %cluster_stats = (
			base_quality    => Statistics::Descriptive::Sparse->new,  
			mapping_quality => Statistics::Descriptive::Sparse->new,
			mismatches      => Statistics::Descriptive::Sparse->new,
			);
		my $lookup   = $chr_to_id{$chr};
		
		####FIRST CALLBACK SUB-ROUTINE FOR ALIGNMENT STATS###	
			
		my $callback = sub {
			my $alignment = shift;
            my $flag = $alignment->flag;
			
			#### LOOKING AT ONLY MAPPED ALIGNMENTS FOR ALIGNMENT STATISTICS #####	
			if ($flag != 4) 		
			{
				$count_of{ $alignment->aux_get("XM") }++;
				$cluster_stats{mismatches}->add_data( $alignment->aux_get("XM") );
				$cluster_stats{mapping_quality}->add_data( $alignment->qual );
				
				if ( $alignment->qual eq '0' ) 
					{
						$CountZeroMapQ++;
						my $query_stop = 0;					
			        }
				my @base_quals 	= $alignment->qscore;
				$cluster_stats{base_quality}->add_data(@base_quals);
				
				my $mm_position = $alignment->aux_get("MD");
				my $strand 		= $alignment -> strand;
				if ($strand eq '1' && $mm_position =~ m/^0[ACTG](\d+)/) ###LOOKING AT 1st POSITION MM FOLLOWING BY >= 16bp MATCHES
				{
					my $i = $1;
					if ($i >= 16)
					{	
						$first_position_mm++;
					}
				}
			    if ($strand eq '-1' && $mm_position =~ m/(\d+)[ACTG]0$/) 
					{
						my $j = $1;
						if ($j >= 16)
						{
                        	$first_position_mm++;
						}
					}
			}
			

		};
		
		$index->fetch( $bam, $lookup, $start, $stop, $callback ); 
		
		my $mean_mapQ  = $cluster_stats{mapping_quality}->mean();
		my $stdev_mapQ = $cluster_stats{mapping_quality}->standard_deviation();
		my $mean_baseQ = $cluster_stats{base_quality}->mean();
	    my $total_alignments = $cluster_stats{mapping_quality}->count();
	   
	    my $Percent_map_z = ($CountZeroMapQ / $total_alignments) * 100;
		my $Percent_map_z_rounded = sprintf("%.2f", $Percent_map_z);
	   
		my $min_mismatch     = $cluster_stats{mismatches}->min();
		my $max_mismatch     = $cluster_stats{mismatches}->max();

		my $normalization_17_70 = $zenith_depth/$flagstat_mapped_17_70 ; 
		my $normalization_bin = $zenith_depth/$flagstat_mapped ; 
		
		print $output_fh join("\t",$name,$chr,$start,$stop,$depth,$zenith_depth,$cluster_length,$normalization_17_70,$normalization_bin). "\t";
		
		################## CALCULATING MISMATCH STATISTICS###
		my $totalMM = 0;
		foreach my $mm ( sort keys %count_of ) 
		{
			if ( $mm != 0 ) 
			{
				$totalMM += $count_of{$mm};
			}
		}
		my $percentMM = $totalMM / $total_alignments;
		print $output_fh sprintf("%.2f", $percentMM *100 ). "\t";

		for ( my $x = 0 ; $x < 5 ; $x++ )
		{
			if ($count_of{$x}) 
			{
				my $percent_x_mm = ( $count_of{$x} ) / $total_alignments;
				print $output_fh sprintf("%.2f", $percent_x_mm *100). "\t";	
			}
			else
			{
				print $output_fh '0'."\t";
			}

		}
		
		my $first_position_mm_percent;
		if ($totalMM != 0)
        {
        	 $first_position_mm_percent = $first_position_mm/$totalMM;
        }
        else 
        {
        	 $first_position_mm_percent = 0;
        	
        }
        print $output_fh  sprintf("%.2f", $first_position_mm_percent *100) . "\t";
		####################################

		print $output_fh sprintf("%.2f",$mean_mapQ) . "\t"
		  . sprintf("%.2f", $stdev_mapQ) . "\t"
		  . sprintf("%.2f", $CountZeroMapQ / $total_alignments) . "\t"
		  . sprintf("%.2f", $mean_baseQ) . "\n";

############ SECOND CALLBACK - LOOKING FOR SUB-CLUSTERS############

		my $second_callback = sub 
		{
		  my $alignment = shift;	
		  my $flag             = $alignment->flag;
		  my $map_score        = $alignment->qual;			
					
		   if ( $flag != 4 &&   $map_score eq '0' && $Percent_map_z_rounded > $cutoff)  
			
			{
				my $subclusters_fh = Genome::Sys->open_file_for_appending($bed_temp_name);	
				my %Xa_hash;
				my $XA_tag = $alignment->aux_get("XA");
				
			    my @XA_splitArr = split( ';', $XA_tag );
				foreach my $arr (@XA_splitArr) 
				{
				 	my @Tag = split( ',', $arr );
					$Xa_hash{'chrom'} = $Tag[0];
					$Tag[1] =~ s/\+/\+,/g;
					$Tag[1] =~ s/\-/\-,/g;
					my @strand = split( ',', $Tag[1] );
					$Xa_hash{'strand'} = $strand[0];
					$Xa_hash{'start'}  = $strand[1];
					$Xa_hash{'CIGAR'}  = $Tag[2];
					my $stop;
					my @stop_arr = split( /[A-Z]/, $Tag[2] );
					$stop += $_ for @stop_arr;
					$Xa_hash{'stop'} = ( $Xa_hash{'start'} + $stop );
				}
				print $subclusters_fh join("\t", $Xa_hash{'chrom'},$Xa_hash{'start'},$Xa_hash{'stop'},$id ) . "\n";
			}

		};
	$index->fetch( $bam, $lookup, $start, $stop, $second_callback );
		
	
	######## MERGING BED FILE TO GET A SUBCLUSTERS BED FILE OF ENTRIES########

		if ( -s $bed_temp_name ) {
			my $merged_bed_temp_name = Genome::Sys->create_temp_file_path();
			unless (
				Genome::Model::Tools::BedTools::Merge->execute(
					input_file    => $bed_temp_name,
					output_file   => $merged_bed_temp_name,
					report_number => 1 )
					)
			{
				die;
			}
			
			
			my $total_sub_depth=0;
			my $j = 0;
			
			my $merged_bed_temp_fh = Genome::Sys->open_file_for_reading($merged_bed_temp_name);
			
			while ( my $line = $merged_bed_temp_fh->getline ) 
			{
				chomp $line;
				my ($sub_chr,$sub_start,$sub_stop,$raw_depth) = split( /\t/, $line );
				$total_sub_depth = $total_sub_depth + $raw_depth;
			}
			
			my $new_merged_bed_temp_fh = Genome::Sys->open_file_for_reading($merged_bed_temp_name);
			
			while ( my $line_new = $new_merged_bed_temp_fh->getline ) 
			{
				$j++;
				chomp $line_new;
				my ($sub_chr,$sub_start,$sub_stop,$raw_depth) = split( /\t/, $line_new );				
				print $sub_output_fh $line_new ."\t".sprintf("%.2f",(($raw_depth/$total_sub_depth) * 100))."\t".$name . "." . $j . "\n";
			}

			unlink $bed_temp_name;
			unlink $merged_bed_temp_name;
		}

	 }} #### CLOSING COVERAGE FILE
	 
	if ( -s $sub_output ) {
		unless (Genome::Model::Tools::BedTools::Intersect->execute(
				input_file_b        => $output_cluster_bed,
				input_file_a_format => 'bed',
				input_file_a        => $sub_output,
				intersection_type   => 'overlap_both',
				output_file         => $self->output_subcluster_intersect_file,
			)
		  )
		  
		{
			die;
		}
		
	}

	return 1;


}
 
1;

__END__

