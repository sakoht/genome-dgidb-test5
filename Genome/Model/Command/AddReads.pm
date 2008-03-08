package Genome::Model::Command::AddReads;

use strict;
use warnings;

use above "Genome";
use Command; 

class Genome::Model::Command::AddReads {
    is => 'Command',
    has => [
        model_id            => { is => 'Integer', 
                                doc => "Identifies the genome model to which we'll add the reads." },
        model               => { is => 'Genome::Model', id_by => 'model_id', constraint_name => 'GME_GM_FK' },
        sequencing_platform => { is => 'String',
                                doc => 'Type of sequencing instrument used to generate the data'},
        full_path           => { is => 'String',
                                doc => 'Pathname for the data produced by the run (GERALD dir for Solexa runs)',
                                is_optional => 1 },
        run_name            => { is => 'String',
                                 doc => "Name of the run.  It will determine the pathname automaticly and add all lanes for the model's sample",
                                 is_optional => 1 },
    ],
    has_optional => [
        limit_regions       =>  { is => 'String',
                                    doc => 'Which regions should be kept during further analysis' },
        bsub                =>  { is => 'Boolean',
                                    doc => 'Sub-commands should be submitted to bsub. Default is yes.',
                                    default_value => 1 },
        bsub_queue          =>  { is => 'String',
                                    doc => 'Which bsub queue to use for sub-command jobs, default is "long"',
                                    default_value => 'long'},
        bsub_args           => { is => 'String',
                                    doc => 'Additional arguments passed along to bsub (such as -o, for example)',
                                    default_value => '' },
        test                => { is => 'Boolean',
                                    doc => 'Create run information in the database, but do not schedule any sub-commands',
                                    is_optional => 1,
                                    default_value => 0},
    ]
};

sub sub_command_sort_position { 3 }

sub help_brief {
    "launch the pipeline of steps which adds reads to a model"
}

sub help_synopsis {
    return <<"EOS"
genome-model add-reads --model-id 5 --squencing-platform solexa --full-path=/gscmnt/sata191/production/TEST_DATA/000000_HWI-EAS110-0000_00000/Data/C1-27_Firecrest1.8.28_04-09-2007_lims/Bustard1.8.28_04-09-2007_lims/GERALD_28-01-2007_mhickenb

genome-model add-reads --model-id 5 --squencing-platform solexa --run_name 000000_HWI-EAS110-0000_00000
EOS
}

sub help_detail {
    return <<"EOS"
This command launches all of the appropriate commands to add a run,
or part of a run, to the specified model.

Either the --full-path or --run-name option must be specified.  

All of the sub-commands listed below will be executed on the model in succession.

EOS
}


our $GENOME_MODEL_BSUBBED_COMMAND = "genome-model";

sub execute {
    my $self = shift;

    my @sub_command_classes = @{ $self->_get_sorted_sub_command_classes };

$DB::single=1;
    # Determine the pathname for the run
    my $full_path;
    if ($self->full_path) {
        $full_path = $self->full_path;

    } elsif ($self->run_name) {
        require GSCApp;
        my @paths = $self->_find_full_path_by_run_name_and_sequencing_platform();

        if (! @paths) {
            @paths = $self->_find_full_path_by_run_name_and_sequencing_platform_old();
        }

        if (! @paths) {
            $self->error_message("No analysis pathname found for that run name");
            return;
        } elsif (@paths > 1) {
            my $message = "Multiple analysis pathnames found:\n" . join("\n",@paths);
            $self->warning_message($message);
            $self->error_message("Use the --full-path option to directly specify one pathname");
            return;
        } else {
            $full_path = $paths[0];
        }
    }

    unless (-d $full_path) {
        $self->error_message("full_path $full_path directory does not exist");
        return;
    }

    # Determine the correct value for limit_regions
    my $regions;
    if ($self->limit_regions) {
        $regions = $self->limit_regions;

    } else {
        # The default will differ depengin on what the sequencing_patform is
        $regions = $self->_determine_default_limit_regions();
    }

    unless ($regions) {
        $self->error_message("limit_regions is empty!");
        return;
    }

    $self->full_path($full_path);
    $self->limit_regions($regions);
    $self->status_message("Using full_path: ".$self->full_path."\nlimit_regions: ".$self->limit_regions);

    # Make a RunChunk object for each region
    my $model = $self->model;
    my @runs;
    foreach my $region ( split(//,$regions) ) {
        my $run = Genome::RunChunk->get_or_create(full_path => $full_path,
                                                  limit_regions => $region,
                                                  sequencing_platform => $self->sequencing_platform,
                                                  sample_name => $model->sample_name,
                                             );
        unless ($run) {
            $self->error_message("Failed to run record information for region $region");
            return;
        }
        push @runs, $run;
    }

    unless (@runs) {
        $self->error_message("No runs were created, exiting.");
        return;
    }

    foreach my $run ( @runs ) {

        my $last_bsub_job_id;
        foreach my $command_class ( @sub_command_classes ) {
            my $command = $command_class->create(run_id => $run->id,
                                                 model_id => $self->model_id);
    
            if ($self->bsub) {
                $last_bsub_job_id = $self->run_command_with_bsub($command,$run,$last_bsub_job_id);
                $command->lsf_job_id($last_bsub_job_id);
            } elsif (! $self->test) {
                $last_bsub_job_id = $command->execute();
            }


            # This will be false if something went wrong.
            # We should probably stop the pipeline at this point
            return unless $last_bsub_job_id;

            # For catching up on all the old runs... remove later
            # This will submit only the assign-run step
            #last;
        }
    }

    return 1; 
}


sub _find_full_path_by_run_name_and_sequencing_platform_old {
    my($self) = @_;

    my $run_name = $self->run_name;
    my $sequencing_platform = $self->sequencing_platform;

    unless ($sequencing_platform eq 'solexa') {
        $self->error_message("Don't know how to determine run paths for sequencing platform $sequencing_platform");
        return;
    }

    my $solexa_run = GSC::Equipment::Solexa::Run->get(run_name => $run_name);
    unless ($solexa_run) {
        $self->error_message("No Solexa run found by that name");
        return;
    }

    my $config_image_analysis_pse = GSC::PSE->get(pse_id => $solexa_run->creation_event_id);
    my $sample_name = $self->model->sample_name();
    my @this_sample_lanes = map { GSC::DNALocation->get($_->dl_id)->location_order }
                            grep { $_->get_dna->dna_name eq $sample_name }
                            GSC::DNAPSE->get(pse_id => $config_image_analysis_pse);

    $self->status_message("Sample $sample_name is in lanes: ".join(',',sort @this_sample_lanes));

    my $glob = $solexa_run->run_directory . '/Data/*Firecrest*/Bustard*/GERALD*/';
    my @possible_gerald_dirs = glob($glob);
    my @gerald_dirs;
    foreach my $gerald_dir ( @possible_gerald_dirs ) {
        my $found = 1;
        foreach my $lane ( @this_sample_lanes ) {
            my $lane_pathname = sprintf('%s/s_%s_sequence.txt', $gerald_dir, $lane);
            unless (-f $lane_pathname) {
                $found = 0;
                last;
            }
        }
        push(@gerald_dirs, $gerald_dir) if $found;
    }

    return @gerald_dirs;
}

# For solexa runs, return the gerald directory path for the 
# analysis on this model's samples
# NOTE: Data is broken on OLTP for flow cell 9133
sub _find_full_path_by_run_name_and_sequencing_platform {
    my $self = shift;

    my $run_name = $self->run_name;
    my $sequencing_platform = $self->sequencing_platform;

    unless ($sequencing_platform eq 'solexa') {
        $self->error_message("Don't know how to determine run paths for sequencing platform $sequencing_platform");
        return;
    }

    my $solexa_run = GSC::Equipment::Solexa::Run->get(run_name => $run_name);
    unless ($solexa_run) {
        $self->error_message("No Solexa run found by that name");
        return;
    }

    my $config_image_analysis_pse = GSC::PSE->get(pse_id => $solexa_run->creation_event_id);
    my $sample_name = $self->model->sample_name();
    my @involved_lanes = map { GSC::DNALocation->get($_->dl_id)->location_order }
                         grep { $_->get_dna->dna_name eq $sample_name }
                         GSC::DNAPSE->get(pse_id => $config_image_analysis_pse);

    unless ( @involved_lanes ) {
        $self->warning_message("Sample $sample_name does not appear to be in this run");
        return;
    }

    my @possible_configure_alignment_pses = grep { $_->process_to eq 'configure alignment' and
                                                   $_->pse_status eq 'completed' and
                                                   $_->pse_result eq 'successful' }
                                            $config_image_analysis_pse->get_subsequent_pses_recurse;
    
    my @config_alignment_pses = grep { my @l = GSC::PSEParam->get(param_name => 'lanes',
                                                                  param_value => \@involved_lanes,
                                                                  pse_id => \@possible_configure_alignment_pses)
                                     }
                                @possible_configure_alignment_pses;
  

    if (@config_alignment_pses != 1) {
        $self->warning_message("Found ".scalar(@config_alignment_pses)." 'configure alignment' PSE for run $run_name, sample $sample_name");
        return;
    }

    my @gerald_dir_param = GSC::PSEParam->get(param_name => 'gerald_directory',
                                              pse_id => $config_alignment_pses[0]);
    unless (@gerald_dir_param) {
        $self->error_message("No gerald_directory PSEParam for pse ".$config_alignment_pses[0]->pse_id);
        return;
    }

    my @gerald_dirs = map { $_->param_value }
                      @gerald_dir_param;

    # the real gerald_dir may have been archived since running gerald.
    # in that case, the run_directory is the right top-level dir, but
    # the rest of the path to the gerald_directory must come from the
    # gerald_directory PSE parameter
    my $run_directory = $solexa_run->run_directory;
    foreach ( @gerald_dirs ) {
        unless (m/^$run_directory/) {
            s/^.*\/$run_name/$run_directory/;
        }
    }

    return @gerald_dirs;
}



sub _determine_default_limit_regions {
    my($self) = @_;

    unless ($self->sequencing_platform eq 'solexa') {
        $self->error_message("Don't know how to determine limit-regions for sequencing platform ".$self->sequencing_platform);
        return;
    }
  
    my $flowcell;
    my $run_name = $self->run_name;
    unless ($run_name) {
        my @path_parts = split('/', $self->full_path);
        foreach my $part ( @path_parts ) {
            ($run_name) = m/.*\/(.*?_\d+_\d+)$/;
            last if $run_name;;
        }
        unless ($run_name) {
            $self->error_message("Couldn't determine run name from --full-path ".$self->full_path);
            return;
        }
    }

    my $solexa_run = GSC::Equipment::Solexa::Run->get(run_name => $run_name);
    unless ($solexa_run) {
        $self->error_message("No Solexa run record for run_name $run_name");
        return;
    }

    my @dnapses = GSC::DNAPSE->get(pse_id => $solexa_run->creation_event_id);
    my $model = Genome::Model->get(genome_model_id => $self->model_id);

    my %location_to_dna =
               map { GSC::DNALocation->get(dl_id => $_->dl_id)->location_order => GSC::DNA->get(dna_id => $_->dna_id) }
               grep { $_->get_dna->dna_name eq $model->sample_name }
               @dnapses;

    return join('',keys %location_to_dna);
}


sub run_command_with_bsub {
    my($self,$command,$run,$last_bsub_job_id) = @_;

    my $queue = $self->bsub_queue;
    my $bsub_args = $self->bsub_args;

    if ($command->can('bsub_rusage')) {
        $bsub_args .= ' ' . $command->bsub_rusage;
    }

    # In case the command to run on the blades is different than 'genome-model'
    my $cmd = $command->command_name;
    $cmd =~ s/^\S+/$GENOME_MODEL_BSUBBED_COMMAND/;

    my $run_id = $run->id;
    my $model_id = $self->model_id;

    my $cmdline;
    { no warnings 'uninitialized';
        $cmdline = "bsub -q $queue $bsub_args" .
                   ($last_bsub_job_id && " -w $last_bsub_job_id") .
                   " $cmd --model-id $model_id --run-id $run_id";
    }

    if ($self->test) {
        #$command->status_message("Test mode, command not executed: $cmdline");
        print "Test mode, command not executed: $cmdline\n";
        $last_bsub_job_id = 'test';
    } else {
        $self->status_message("Running command: " . $cmdline);

        my $bsub_output = `$cmdline`;
        my $retval = $? >> 8;

        if ($retval) {
            $self->error_message("bsub returned a non-zero exit code ($retval), bailing out");
            return;
        }

        if ($bsub_output =~ m/Job <(\d+)>/) {
            $last_bsub_job_id = $1;

        } else {
            $self->error_message('Unable to parse bsub output, bailing out');
            $self->error_message("The output was: $bsub_output");
            return;
        }

    }

    return $last_bsub_job_id;
}



sub _get_sorted_sub_command_classes{
    my $self = shift;

    # Determine what all the sub-commands are going to be
    my @sub_command_classes = sort { $a->sub_command_sort_position
                                     <=>
                                     $b->sub_command_sort_position
                                   } grep {! $_->can('is_not_to_be_run_by_add_reads')} $self->sub_command_classes();
    
    return \@sub_command_classes;
}

1;

