
package Genome::Model::Tools::Capture::ModelGroup;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# ModelGroup - Build Genome Models for Capture Datasets
#					
#	AUTHOR:		Dan Koboldt (dkoboldt@genome.wustl.edu)
#
#	CREATED:	12/09/2009 by D.K.
#	MODIFIED:	12/09/2009 by D.K.
#
#	NOTES:	
#			
#####################################################################################################################################

use strict;
use warnings;

use FileHandle;

use Genome;                                 # using the namespace authorizes Class::Autouse to lazy-load modules under it

## Declare global statistics hash ##

my %stats = ();

class Genome::Model::Tools::Capture::ModelGroup {
	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		group_id		=> { is => 'Text', doc => "ID of model group" , is_optional => 0},
		output_bam_files	=> { is => 'Text', doc => "Optional output file for BAMs of completed samples" , is_optional => 1},
		output_snp_files	=> { is => 'Text', doc => "Optional output file for SNP calls for completed samples" , is_optional => 1},
		output_model_pairs	=> { is => 'Text', doc => "Optional output file for paired normal-tumor model ids" , is_optional => 1},
		show_builds	=> { is => 'Text', doc => "Show build IDs and statuses" , is_optional => 1},
		show_lanes	=> { is => 'Text', doc => "Show lane details for instrument data" , is_optional => 1},
		tcga_fix	=> { is => 'Text', doc => "Shorten/simplify TCGA sample names" , is_optional => 1},
	],
};

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
    "Operate on capture reference alignment model groups"                 
}

sub help_synopsis {
    return <<EOS
Operate on capture reference alignment model groups
EXAMPLE:	gmt capture build-models --group-id 661
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

	my $group_id = $self->group_id;

	## Open Optional Output Files ##

	if($self->output_bam_files)
	{
		open(BAMLIST, ">" . $self->output_bam_files) or die "Can't open outfile: $!\n";
	}

	if($self->output_snp_files)
	{
		open(SNPLIST, ">" . $self->output_snp_files) or die "Can't open outfile: $!\n";
	}

	if($self->output_model_pairs)
	{
		open(MODELPAIRS, ">" . $self->output_model_pairs) or die "Can't open outfile: $!\n";
	}
	
	
	## Keep stats in a single hash ##
	
	my %stats = ();
	
	## Save model ids by subject name ##
	
	my %succeeded_models_by_sample = ();

	## Get the models in each model group ##

	my $model_group = Genome::ModelGroup->get($group_id);
	my @models = $model_group->models; 

	foreach my $model (@models)
	{
		$stats{'models_in_group'}++;
		
		my $model_id = $model->genome_model_id;
		my $subject_name = $model->subject_name;

		## TCGA FIX ##	
		if($self->tcga_fix)
		{
			$subject_name = substr($subject_name, 0, 19) . "-1";		
		}
		
		my $build_dir = my $bam_file = my $snp_file = "";
		my $model_status = "New";


		my $num_builds = 0;		

		my $build_ids = my $build_statuses = "";
		my @builds = $model->builds;

		if($self->show_builds)
		{
			foreach my $build (@builds)
			{
				$num_builds++;
				$build_ids .= "," if($build_ids);
				$build_statuses .= "," if($build_statuses);
				$build_ids .= $build->id;
				$build_statuses .= $build->status;
			}
		}
		
		my $num_lanes = 0;
		my $lane_details = "";

		if($self->show_lanes)
		{
			## Get Assigned Instrument Data ##
			my @instrument_data = $model->assigned_instrument_data;
			
			foreach my $instrument_data (@instrument_data)
			{
				$num_lanes++;
				if($self->show_lanes)
				{
					## Show lane details ##
					$lane_details .= ", " if($lane_details);
					$lane_details .= join(":", $instrument_data->flow_cell_id, $instrument_data->lane);
				}
			}
		}
		
		
		if(@builds)
		{
			$model_status = "Run";
			if($model->last_succeeded_build_directory)
			{
				$model_status = "Done";
				$stats{'models_finished'}++;
				
				$succeeded_models_by_sample{$subject_name} = $model_id;
				
				$build_dir = $model->last_succeeded_build_directory;
				
				## Get the BAM file ##

				my $search_string = "ls " . $model->last_succeeded_build_directory . "/alignments/*.bam 2>/dev/null | tail -1";
				my $bam_list_result = `$search_string`;
				chomp($bam_list_result);

				if($bam_list_result && -e $bam_list_result)
				{
					$bam_file = $bam_list_result;
					print BAMLIST "$subject_name\t$bam_file\n" if($self->output_bam_files);
				}


				## Get the SNP file ##
				
				if($self->output_snp_files)
				{
					my $search_string = "ls " . $model->last_succeeded_build_directory . "/sam*/filtered.indelpe.snps 2>/dev/null | tail -1";
					my $snp_list_result = `$search_string`;
					chomp($snp_list_result) if($snp_list_result);
					if(!$snp_list_result)
					{
						$search_string = "ls " . $model->last_succeeded_build_directory . "/snp*/snps_all_sequences.filtered 2>/dev/null | tail -1";
						$snp_list_result = `$search_string`;
						chomp($snp_list_result) if($snp_list_result);						
					}

					if($snp_list_result && -e $snp_list_result)
					{
						$snp_file = $snp_list_result;
						print SNPLIST "$subject_name\t$snp_file\n";
					}
				}
			}
			else
			{
				$stats{'models_running'}++;
			}
		}

		print join("\t", $model_id, $subject_name, $model_status, $num_builds, $build_ids, $build_statuses, $build_dir, $num_lanes, $lane_details) . "\n";

	}	
	
	close(BAMLIST) if($self->output_bam_files);
	close(SNPLIST) if($self->output_snp_files);	

	print $stats{'models_in_group'} . " models in group\n" if($stats{'models_in_group'});
	print $stats{'models_running'} . " models running\n" if($stats{'models_running'});
	print $stats{'models_finished'} . " models finished\n" if($stats{'models_finished'});



	## Determine normal-tumor pairing and completed models ##
	if($self->output_model_pairs)
	{
		my %tumor_sample_names = my %tumor_model_ids = my %normal_model_ids = ();
	
		foreach my $sample_name (keys %succeeded_models_by_sample)
		{
			my $model_id = $succeeded_models_by_sample{$sample_name};
			## Determine patient ID ##
			
			my @tempArray = split(/\-/, $sample_name);
			my $patient_id = join("-", $tempArray[0], $tempArray[1], $tempArray[2]);
			
			## Determine if this sample is normal or tumor ##
			
			my $sample_type = "tumor";
			$sample_type = "normal" if(substr($tempArray[3], 0, 1) eq "1");
	
			if($sample_type eq "tumor")
			{
				$tumor_model_ids{$patient_id} = $model_id;
				$tumor_sample_names{$patient_id} = $sample_name;
			}
			elsif($sample_type eq "normal")
			{
				$normal_model_ids{$patient_id} = $model_id;
			}
			
	#		print "$sample_name\t$patient_id\t$sample_type\n";
		}
		
		foreach my $patient_id (sort keys %tumor_model_ids)
		{
			$stats{'num_patients'}++;
			
			if($normal_model_ids{$patient_id})
			{
				$stats{'num_completed_patients'}++;
	
				my $tumor_sample_name = $tumor_sample_names{$patient_id};
				my $tumor_model_id = $tumor_model_ids{$patient_id};
				my $normal_model_id = $normal_model_ids{$patient_id};
	
				if($self->output_model_pairs)
				{
					print MODELPAIRS "$tumor_sample_name\t$normal_model_id\t$tumor_model_id\n";
				}
	
	#			print "$patient_id\t$tumor_sample_name\t$normal_model_id\t$tumor_model_id\n";
			}
	
		}
		
		close(MODELPAIRS) if($self->output_model_pairs);

		print $stats{'num_patients'} . " patients with models in group\n" if($stats{'num_patients'});
		print $stats{'num_completed_patients'} . " patients with completed tumor+normal builds\n" if($stats{'num_completed_patients'});
		
	}


}




1;

