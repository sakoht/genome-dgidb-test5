package Genome::Model::Tools::SmallRna::Spreadsheet;

#08.25.2011
# import new annotation features

#10/13/2011
# added two additional column names for normalization in column header

use strict;
use warnings;
use Bio::DB::Sam;
use Statistics::Descriptive;
use Data::Dumper;
use Genome;

my $DEFAULT_CLUSTERS = '5000';

class Genome::Model::Tools::SmallRna::Spreadsheet {
	is        => ['Genome::Model::Tools::SmallRna::Base'],
	has_input => [
		input_stats_file => {
			is  => 'Text',
			doc => 'Input Statistics File from stats-generator',
		},
		input_intersect_file => {
			is  => 'Text',
			doc => 'Input TSV file from annotate-cluster',
		},
		output_spreadsheet => {
			is => 'Text',
			is_output=> 1,
			doc =>'Output speadsheet containing statistics as well as annotation for each cluster in the stats file',
		},
		input_cluster_number => {
            is => 'Text',
            is_optional => 1,
            doc => 'Number of TOP Clusters to calculate statistcs',
            default_value => $DEFAULT_CLUSTERS,
	   },

	],
};

sub execute {
    my $self = shift;
    my $stats 		= $self->input_stats_file;
    my $annotation 	= $self->input_intersect_file;
    my $output 		= $self->output_spreadsheet;
    my $clusters 	= $self->input_cluster_number;
    
    
    my ($sorted_temp_fh, $sorted_temp_name) = Genome::Sys->create_temp_file();
    
    my $cmd = 'head -'.$clusters.' '.$annotation .'> '.$sorted_temp_name;
    
    Genome::Sys->shellcmd(
        cmd => $cmd,
        input_files => [$self->input_intersect_file],
        output_files => [$sorted_temp_name],
        skip_if_output_is_present => 0,
    );
    
    my $output_fh = Genome::Sys->open_file_for_writing($output);

    	my %id_hash;
    	my %size_hash;
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
				"Avg BaseQ")	;
		
	my $annotation_fh = Genome::Sys->open_file_for_reading( $sorted_temp_name);		
		
	while (my $anno_row = $annotation_fh->getline) 
		{
			chomp $anno_row;
			my @array_ids = split(/\t/,$anno_row);
			my $size = scalar(@array_ids); 
    		if ($anno_row =~ /^Cluster/)
    		{
    			print $output_fh "\t". join("\t",@array_ids[4 .. $size -1])."\n";
    			
    		}
    		else
    		{
    			my $anno_cluster = $array_ids[0];
    		    my $anno_chr	 = $array_ids[1];
    		   	my $anno_start 	 = $array_ids[2];
    		    my $anno_stop 	 = $array_ids[3];
    		    
				my $stats_fh = Genome::Sys->open_file_for_reading( $stats);
	    	    while (my $row = $stats_fh->getline) 
	    	    {	
    				chomp $row;		    
    				my ($name,$chr,$start,$stop) = split ("\t", $row);	
    		   		
    		   		if ($chr eq $anno_chr && $start eq $anno_start && $stop eq $anno_stop )
    		    	{
  						print $output_fh $row."\t". join("\t",@array_ids[4 .. $size -1])."\n";
    		    	}
    			}
    		}
    		
  		}
    	    	
return 1;
    
}
1;	

