package Genome::Model::Command::Services::AssignQueuedInstrumentData;

use strict;
use warnings;

#use Genome;

require Carp;
use Data::Dumper;

class Genome::Model::Command::Services::AssignQueuedInstrumentData {
    is  => 'Command',
    has => [
        test => {
            is          => 'String',
            doc         => "This parameter, if set true, will only process pses with negative id's.",
            is_optional => 1,
            default     => (Genome::Config->dev_mode),
        },
        max_pses => {
            is          => 'Number',
            is_optional => 1,
            len         => 5,
            default     => 200,
            doc         => 'Max # of PSEs to process in one invocation',
        },
        max_pses_to_check => {
            is          => 'Number',
            is_optional => 1,
            len         => 5,
            default     => 1000,
            doc         => 'Max # of PSEs to check for processability',
        },
        newest_first => {
            is          => 'Boolean',
            is_optional => 1,
            default     => 0,
            doc         => 'Process newest PSEs first',
        },
        pse_id => {
            is          => 'Number',
            is_optional => 1,
            doc         => 'Ignore other parameters and only process this PSE.',
        },
        _existing_models_with_existing_assignments => {
            is => 'HASH',
            doc => 'Existing models that already had the instrument data for a PSE assigned',
            default_value => {},
            is_output => 1,
        },
        _existing_models_assigned_to => {
            is => 'HASH',
            doc => 'Existing models with the instrument data for a PSE newly assigned',
            default_value => {},
            is_output => 1,
        },
        _newly_created_models => {
            is => 'HASH',
            doc => 'New models created for the instrument data for a PSE',
            default_value => {},
            is_output => 1,
        },
    ],
};

sub _default_mc16s_processing_profile_id {
    # RT66900 was 2278045
    return 2571784;
}

sub _default_de_novo_assembly_bacterial_processing_profile_id {
    return 2682126;
}

sub _default_rna_seq_processing_profile_id {
    return 2623697;
}

#FIXME: This should be refactored so that %known_454_pipelines and
#%known_454_16s_pipelines are merged into a single hash.  Key shoud be the
#pipeline name and value should be what to do with it (if anything).  Maybe
#processing_profile if if we do something with it and empty string if we ignore
#it.
our %known_454_pipelines =
    map { $_ => 1}
    (
        '16S 3730 Sequencing',
        '16S 3730 Sequencing - Unknown Reference Strain',
        '16S 454',
        '16S 454 Sequencing',
        '3730 384 Subclone',
        '3730 96 Subclone',
        '3730 BAC',
        '3730 Fosmid',
        '3730 Ligation',
        '3730 PCR',
        '3730 PCR-based Amplicon Re-sequencing',
        '3730 SeqDNA',
        '3730 Subclone DNA',
        '454 Titanium',
        '454 Titanium Fragment',
        '454 Titanium Paired End',
        'Agilent Sure Select Whole Exome Capture Illumina',
        'Analysis',
        'Automated Library Construction Illumina',
        'Finishing gDNA for PCR Request',
        'Genotyping Pipeline',
        'HMP Resource Storage',
        'Illumina',
        'Illumina Sequencing',
        'Nimblegen Custom Capture Illumina',
        'Nimblegen Whole Exome Capture Illumina',
        'PCR-based 454',
        'PCR-based Illumina',
        'Production Library Construction and Technology Development Illumina',
        'Resource Storage',
        'Technology Development 16S 454',
        'Technology Development Capture',
        'Technology Development Library Construction and Production 454',
        'Technology Development Library Construction and Production Illumina',
        'Technology Development Library Construction and Tech D Illumina',
        'Transcript Mutation Validation - 3730 PCR Pipeline',
        'Transcript Mutation Validation - 454 Titanium Fragment Pipeline',
        'Transcript Mutation Validation - Illumina Sequencing Pipeline',
        'Technology Development Library Construction Illumina',
        'WUCAP Custom Capture Illumina',
    );


our %known_454_16s_pipelines =
    map { $_ => 1 }
    (
        '16S 454',
        '16S 454 Sequencing',
        '16S 3730 Sequencing',
        '16S 3730 Sequencing - Unknown Reference Strain',
        'Technology Development 16S 454',
    );

sub help_brief {
'Find all QueueInstrumentDataForGenomeModeling PSEs, create appropriate models, assign instrument data, and finally request a build on the model';
}

sub help_synopsis {
    return <<'EOS'
EOS
}

sub help_detail {
    return <<EOS
EOS
}

sub get_organism_taxon {
    my $sample = shift;
    my $population = get_population($sample);
    if ($population){
        return $population->taxon;
    }
    if(!$sample->taxon_id){
        return $sample->patient->taxon if $sample->patient;
    }
    return $sample->taxon;
}

sub get_population {
    my $sample = shift;
    my $source_type = $sample->source_type;
    if($source_type &&
            ($source_type eq 'organism individual' ||
             $source_type eq 'population group')){
        return $sample->source;
    }
    return;
}

sub execute {
    $DB::single = $DB::stopper;
    my $self = shift;

    my $lock;
    unless($self->test) {
        my $lock_resource = '/gsc/var/lock/genome_model_command_services_assign-queued-instrument-data/loader';

        $lock = Genome::Sys->lock_resource(resource_lock=>$lock_resource, max_try=>1);
        unless ($lock) {
            $self->error_message("could not lock, another instance must be running.");
            return;
        }

        UR::Context->current->add_observer(
            aspect => 'commit',
            callback => sub{
                Genome::Sys->unlock_resource(resource_lock=>$lock);
            }
        )
    }

    my @pses = $self->load_pses;
    $self->status_message('Processing '.scalar(@pses).' PSEs');
    return 1 unless scalar @pses;

    $self->add_processing_profiles_to_pses(@pses);

    my @completable_pses;

    PSE:
    foreach my $pse (@pses) {
        $self->status_message('Starting PSE ' . $pse->id);

        my ($instrument_data_type) = $pse->added_param('instrument_data_type');
        my ($instrument_data_id)   = $pse->added_param('instrument_data_id');
        my ($subject_class_name)   = $pse->added_param('subject_class_name');
        my ($subject_id)           = $pse->added_param('subject_id');

        my @processing_profile_ids = $pse->added_param('processing_profile_id');

        if ( $instrument_data_type =~ /sanger/i ) {
            #for sanger data the pse param actually holds the id of an AnalyzeTraces PSE.
            my $analyze_traces_pse = GSC::PSE::AnalyzeTraces->get($instrument_data_id);

            my $run_name = $analyze_traces_pse->run_name();
            $instrument_data_id = $run_name;
        }

        my $genome_instrument_data = Genome::InstrumentData->get( id => $instrument_data_id );

        if($genome_instrument_data->ignored() ) {
            next;
        }

        my @process_errors;

        if ($subject_class_name and $subject_id and @processing_profile_ids) {
            my $subject      = $subject_class_name->get($subject_id);

            if ( $instrument_data_type =~ /454/i and $subject->name eq 'n-ctrl' ) { 
                # Do not process 454 negative control (n-ctrl)
                $self->status_message('Skipping n-ctrl PSE '.$pse->id);
                next PSE;
            }

            PP:
            foreach my $processing_profile_id (@processing_profile_ids) {
                my $processing_profile = Genome::ProcessingProfile->get( $processing_profile_id );

                unless ($processing_profile) {
                    $self->error_message(
                        'Failed to get processing profile'
                        . " '$processing_profile_id' for inprogress pse "
                        . $pse->pse_id );
                    push @process_errors, $self->error_message;
                    next PP;
                }

                my @reference_sequence_builds = ( undef ); # this allows to use a loop to assign
                # These pps require imported reference seq build
                if( $processing_profile->isa('Genome::ProcessingProfile::ReferenceAlignment')
                        or $processing_profile->isa('Genome::ProcessingProfile::GenotypeMicroarray')
                        or $processing_profile->isa('Genome::ProcessingProfile::RnaSeq')) {
                    my @reference_sequence_build_ids = $pse->reference_sequence_build_param_for_processing_profile($processing_profile);
                    if ( not @reference_sequence_build_ids ) {
                        $self->error_message('No imported reference sequence build id found on pse ('.$pse->id.') to create '.$processing_profile->type_name.' model');
                        push @process_errors, $self->error_message;
                        next PP;
                    }

                    @reference_sequence_builds = Genome::Model::Build::ImportedReferenceSequence->get(\@reference_sequence_build_ids);
                    if ( not @reference_sequence_builds or @reference_sequence_builds ne @reference_sequence_build_ids ) {
                        $self->error_message("Failed to get imported reference sequence builds for ids: @reference_sequence_build_ids");
                        push @process_errors, $self->error_message;
                        next PP;
                    }

                }

                my @models = Genome::Model->get(
                    subject_id            => $subject_id,
                    processing_profile_id => $processing_profile->id,
                    auto_assign_inst_data => 1,
                );

                for my $reference_sequence_build ( @reference_sequence_builds ) {
                    my @assigned = $self->assign_instrument_data_to_models($genome_instrument_data, $reference_sequence_build, @models);

                    #returns an explicit undef on error
                    if(scalar(@assigned) eq 1 and not defined $assigned[0]) {
                        push @process_errors, $self->error_message;
                        next PP;
                    }

                    if(scalar(@assigned > 0)) {
                        for my $m (@assigned) {
                            $pse->add_param('genome_model_id', $m->id);
                        }
                        #find or create default qc models if applicable
                        $self->create_default_qc_models(@assigned);
                        #find or create somatic models if applicable
                        $self->find_or_create_somatic_variation_models(@assigned);

                    } else {
                        # no model found for this PP, make one (or more) and assign all applicable data
                        $DB::single = $DB::stopper;
                        my @new_models = $self->create_default_models_and_assign_all_applicable_instrument_data($genome_instrument_data, $subject, $processing_profile, $reference_sequence_build, $pse);
                        unless(@new_models) {
                            push @process_errors, $self->error_message;
                            next PP;
                        }
                        #find or create somatic models if applicable
                        $self->find_or_create_somatic_variation_models(@new_models);
                    }
                }

                if ( $instrument_data_type eq '454' and $self->_is_454_16s($pse) ) {
                    $self->_find_or_create_mc16s_454_qc_model($genome_instrument_data);
                }
            } # looping through processing profiles for this instdata, finding or creating the default model
        } elsif ( $instrument_data_type =~ /solexa/i
                  and $genome_instrument_data->target_region_set_name
                  and Genome::FeatureList->get(name => $genome_instrument_data->target_region_set_name)
                  and Genome::FeatureList->get(name => $genome_instrument_data->target_region_set_name)->content_type eq 'validation'
                ) {
            my @validation = Genome::Model::SomaticValidation->get(
                target_region_set_name => $genome_instrument_data->target_region_set_name,
                #subject => $genome_instrument_data->sample->source, #due to bad data-tracking, sometimes the two samples are from different sources
            );

            @validation = grep((($_->tumor_sample and $_->tumor_sample eq $genome_instrument_data->sample) or ($_->normal_sample and $_->normal_sample eq $genome_instrument_data->sample)), @validation);
            if(@validation) {
                my $ok = $self->assign_instrument_data_to_models($genome_instrument_data, Genome::FeatureList->get(name => $genome_instrument_data->target_region_set_name)->reference, @validation);
                unless($ok) {
                    push @process_errors,
                        $self->error_message('Did not assign validation instrument data to any models.');
                }
            } elsif($genome_instrument_data->index_sequence eq 'unknown' && $genome_instrument_data->sample->name =~ /Pooled_Library/) {
                $self->status_message('Skipping pooled library validation data.');
                $pse->add_param('no_model_generation_attempted',1);
            } else {
                push @process_errors,
                    $self->error_message('No validation models found to assign data (target ' . $genome_instrument_data->target_region_set_name . ' on instrument data ' . $genome_instrument_data->id . '.)');
            }
        } else {
            #record that the above code was skipped so we could reattempt it if more information gained later
            $pse->add_param('no_model_generation_attempted',1);
            $self->status_message('No model generation attempted for PSE ' . $pse->id);
        } # done with PSEs which specify a $subject_class_name, $subject_id, and @processing_profile_ids

        if (!$subject_class_name or !$subject_id) {
            $self->warning_message(
                "PSE " . $pse->id . " no subject class/id for instrument data $instrument_data_type $instrument_data_id"
                . " (subject_class_name $subject_class_name subject_id $subject_id)"
            );
        }

        # Handle this instdata for other models besides the default
        {
            my $sequencing_platform = $instrument_data_type;

            # Mismatch between the valid values for a sequencing platform via
            # a processing profile and what is stored as the
            # instrument_data_type PSE param
            if ($sequencing_platform eq 'sanger') {
                $sequencing_platform = '3730';
            }

            my @found_models;
            my @check = qw/sample taxon/;

            for my $check (@check) {
                my $subject = $genome_instrument_data->$check;
                # Should we just hoise this check out of the loop and skip to next PSE?
                if (defined($subject)) {
                    my @some_models= Genome::Model->get(
                        subject_id         => $subject->id,
                        auto_assign_inst_data => 1,
                    );

                    my $new_models = $self->_newly_created_models;
                    @some_models = grep { not $new_models->{$_->id} } @some_models;
                    push @found_models,@some_models;
                }
            }

            @found_models =
                grep {
                    $_->processing_profile->can('sequencing_platform')
                } @found_models;

            @found_models =
                grep {
                    $_->processing_profile->sequencing_platform() eq $sequencing_platform
                } @found_models;

            #Don't care here what ref. seq. was used (if any)
            my @assigned = $self->assign_instrument_data_to_models($genome_instrument_data, undef, @found_models);
            if(scalar(@assigned) eq 1 and not defined $assigned[0]) {
                push @process_errors, $self->error_message;
            }
        } # end of adding instdata to non-autogen models


        if (@process_errors > 0) {
            $self->error_message(
                "Leaving queue instrument data PSE inprogress, due to errors. \n"
                    . join("\n",@process_errors)
            );
        }
        else {
            # Set the pse as completed since this is the end of the line
            # for the pses
            push @completable_pses, $pse;
        }

    } # end of PSE loop

    #schedule new builds for the models we found and stored in the output hashes
    $self->request_builds;

    $self->status_message("Completing PSEs...");
    for my $pse (@completable_pses) {
        $pse->pse_status("completed");
    }

    return 1;
}

sub find_or_create_somatic_variation_models{
    my ($self, @models) = @_;
    #only want sample-based models
    @models = grep { $_->subject_class_name eq 'Genome::Sample' } @models;
    #only want TCGA models
    @models = grep {$self->is_tcga_reference_alignment($_) } @models;
    #We want capture models with one of the given roi_set_names and all non capture models here.  Filter the rest out
    @models = grep {defined($_->region_of_interest_set_name) ? $_->region_of_interest_set_name =~ m/agilent.sureselect.exome.version.2.broad.refseq.cds.only/ : 1} @models;
    for my $model (@models){
        my $sample = $model->subject;
        #find or create mate ref-align model
        if ($sample->name =~ m/([^-]+-[^-]+-[^-]+-)([01]{2}A)(.*)/){
            my ($prefix, $designator, $suffix) = ($1, $2, $3);
            my %designator_pairing = (
                '10A' => '01A',
                '01A' => '10A',
            );
            my $mate_designator = $designator_pairing{$designator};
            $self->error_message("Not processing somatic variation model with sample name: " . $sample->name . " and designator: $designator") and next unless $mate_designator;
            my $mate_name = join("", $prefix, $mate_designator, $suffix);

            my $subject_for_mate = Genome::Sample->get(name => $mate_name);
            $self->error_message("No sample found for mate_name $mate_name (paired to: " . $model->name . ")") and next unless $subject_for_mate;

            my %mate_params = (
                subject_id => $subject_for_mate->id,
                reference_sequence_build => $model->reference_sequence_build,
                processing_profile => $model->processing_profile,
                auto_assign_inst_data => '1',
            );
            $mate_params{annotation_reference_build_id} = $model->annotation_reference_build_id if $model->can('annotation_reference_build_id') and $model->annotation_reference_build_id;
            $mate_params{target_region_set_name} = $model->target_region_set_name if $model->can('target_region_set_name') and $model->target_region_set_name;
            $mate_params{region_of_interest_set_name} = $model->region_of_interest_set_name if $model->can('region_of_interest_set_name') and $model->region_of_interest_set_name;

            $DB::single = $DB::stopper;
            my ($mate) = Genome::Model::ReferenceAlignment->get( %mate_params );
            unless ($mate){
                $mate = $model->copy(
                    name => 'AQID-PLACE_HOLDER',
                    instrument_data => undef,
                );
                $self->error_message("Failed to find copied mate with subject name: $mate_name") and next unless $mate;

                $mate->subject_id($subject_for_mate->id);

                my $capture_target = eval{$model->target_region_set_name};
                my $mate_model_name = $mate->default_model_name(capture_target => $capture_target);
                $self->error_message("Could not name mate model for with subject name: $mate_name") and next unless $mate_model_name;
                $mate->name($mate_model_name);
                $mate->auto_assign_inst_data(1);
                $mate->build_requested(0, 'AQID: newly created mate for creating somatic-variation model--has no instrument data');

                my $new_models = $self->_newly_created_models;
                $new_models->{$mate->id} = $mate;
            }

            my %somatic_params = (
                auto_assign_inst_data => 1,
                );
            $somatic_params{annotation_build} = Genome::Model::ImportedAnnotation->annotation_build_for_reference($model->reference_sequence_build);
            $self->error_message('Failed to get annotation_build for somatic variation model with model: ' . $model->name) and next unless $somatic_params{annotation_build};
            $somatic_params{previously_discovered_variations_build} = Genome::Model::ImportedVariationList->dbsnp_build_for_reference($model->reference_sequence_build);
            $self->error_message('Failed to get previously_discovered_variations_build for somatic variation model with model: ' . $model->name) and next unless $somatic_params{previously_discovered_variations_build};

            my $capture_somatic_processing_profile_id = '2642139'; #Nov. 2011 somatic-variation exome
            my $somatic_processing_profile_id = '2642137'; #Nov. 2011 somatic-variation wgs
            my $capture_target = eval{$model->target_region_set_name};
            if($capture_target){
                $somatic_params{processing_profile_id} = $capture_somatic_processing_profile_id;
            }
            else{
                $somatic_params{processing_profile_id} = $somatic_processing_profile_id;
            }
            if ($designator eq '10A'){ #$model is normal
                $somatic_params{normal_model} = $model;
                $somatic_params{tumor_model} = $mate;
            }elsif ($designator eq '01A'){ #$model is tumor
                $somatic_params{tumor_model} = $model;
                $somatic_params{normal_model} = $mate;
            }else{
                die $self->error_message("Serious error in sample designators for automated create of somatic-variation models for ".$model->subject_name);
            }

            my $somatic_variation = Genome::Model::SomaticVariation->get(%somatic_params);

            unless ($somatic_variation){
                $somatic_params{model_name} = 'AQID-PLACE_HOLDER';
                my $create = Genome::Model::Command::Define::SomaticVariation->execute( %somatic_params );
                $self->error_message('Failed to create somatic variation model with component model: ' . $model->name) and next unless $create;

                delete $somatic_params{model_name};
                $somatic_params{name} = 'AQID-PLACE_HOLDER';
                $somatic_variation = Genome::Model::SomaticVariation->get(%somatic_params);
                $self->error_message("Failed to find new somatic variation model with component model: " . $model->name) and next unless $somatic_variation;

                $somatic_variation->build_requested(0, 'AQID: somatic variation build is not ready until ref. align. builds finish');
                my $somatic_variation_model_name = $somatic_variation->default_model_name(capture_target => $capture_target);
                $self->error_message("Failed to name new somatic variation model with component model: " . $model->name) and next unless $somatic_variation_model_name;
                $somatic_variation->name($somatic_variation_model_name);

                my $new_models = $self->_newly_created_models;
                $new_models->{$somatic_variation->id} = $somatic_variation;
            }
        }
        else{
            $self->error_message("Not processing somatic variation model with sample name: " . $model->subject_name);
        }


    }
}


sub root_build37_ref_seq {
    my $self = shift;
    my $root_build37_ref_seq = Genome::Model::Build::ImportedReferenceSequence->get(name => 'GRCh37-lite-build37') || die;
    return $root_build37_ref_seq;
}


sub tcga_roi_for_model {
    my $self = shift;
    my $model = shift;

    my $reference_sequence_build = $model->reference_sequence_build;

    my $root_build37_ref_seq = $self->root_build37_ref_seq;
    my $tcga_cds_roi_list;
    if($reference_sequence_build and $reference_sequence_build->is_compatible_with($root_build37_ref_seq)) {
        $tcga_cds_roi_list = 'agilent_sureselect_exome_version_2_broad_refseq_cds_only_hs37';
    }
    else {
        $tcga_cds_roi_list = 'agilent sureselect exome version 2 broad refseq cds only';
    }

    return $tcga_cds_roi_list;
}

sub is_tcga_reference_alignment {
    my $self = shift;
    my $model = shift;
    my $sample = $model->subject;

    return unless $model->isa('Genome::Model::ReferenceAlignment');
    return if ($model->isa('Genome::Model::ReferenceAlignment') && $model->is_lane_qc);

    #try the extraction label
    my @results = grep {$_->attribute_label eq 'extraction_label' and $_->attribute_value =~ m/^TCGA/} $sample->attributes;
    return 1 if @results;

    #otherwise, check the nomenclature
    my @nomenclature = map { $_->nomenclature } ($sample, $sample->attributes);
    return grep { $_ && $_ =~ /^TCGA/i } @nomenclature;
}

sub load_pses {
    my $self = shift;

    my $pse_sorter;

    if ($self->newest_first) {
        $pse_sorter = sub { $b->id <=> $a->id };
    }
    else {
        $pse_sorter = sub { $a->id <=> $b->id };
    }

    my @pses;
    if($self->pse_id) { #process a specific PSE
        @pses = GSC::PSE->get(
            ps_id => 3733,
            pse_status => 'inprogress',
            id => $self->pse_id,
        );
    } else {
        @pses = GSC::PSE->get(
            ps_id      => 3733,
            pse_status => 'inprogress',
        );

        if($self->test) {
            @pses = grep($_->pse_id < 0, @pses);
        }
    }
    return unless @pses;

    @pses = sort $pse_sorter @pses;

    $self->status_message('Found '.scalar(@pses));

    # Don't try to check more PSEs than we might be able to hold information for in memory.
    if(scalar(@pses) > $self->max_pses_to_check) {
        @pses = splice(@pses, 0, $self->max_pses_to_check);
        $self->status_message('Limiting checking to ' . $self->max_pses_to_check);
    }

    $self->preload_data(@pses); #The checking uses this data, so need to load it first

    @pses = grep($self->check_pse($_), @pses);
    $self->status_message('Of those, '.scalar(@pses). ' PSEs passed check_pse.');

    # Don't bite off more than we can process in a couple hours
    my $max_pses = $self->max_pses;

    if (@pses > $max_pses) {
        @pses = splice(@pses, 0, $max_pses);
        $self->status_message('Limiting processing to ' . $max_pses);
    }

    return @pses;
}

#for efficiency--load these together instead of separate queries for each one
sub preload_data {
    my $self = shift;
    my @pses = @_;

    my @pse_params = GSC::PSEParam->get(pse_id => [ map { $_->pse_id } @pses ]);

    my @instrument_data_ids =
    map { $_->param_value }
    grep { $_->param_name eq 'instrument_data_id' }
    @pse_params;

    $self->status_message("Pre-loading " . scalar(@instrument_data_ids) . " instrument data");
    my @instrument_data = Genome::InstrumentData->get(\@instrument_data_ids);
    my @sample_ids = map { $_->sample_id } @instrument_data;

    $self->status_message("Pre-loading " . scalar(@sample_ids) . " samples");
    my @samples = Genome::Sample->get(\@sample_ids);

    $self->status_message("Pre-loading models for " . scalar(@sample_ids) . " samples");
    my @models = Genome::Model->get(subject_id => \@sample_ids);
    $self->status_message("  got " . scalar(@models) . " models");

    my %taxon_ids = map { $_->taxon_id => 1 } grep($_->taxon_id, @samples);
    my @taxon_ids = sort keys %taxon_ids;
    $self->status_message("Pre-loading models for " . scalar(@taxon_ids) . " taxons");
    push @models, Genome::Model->get(subject_id => \@taxon_ids);
    $self->status_message("  got " . scalar(@models) . " models");

    if(scalar @models > 0) {
        $self->status_message("Pre-loading instrument data inputs for " . scalar(@models) . " models");
        my @instrument_data_inputs = Genome::Model::Input->get(model_id => [ map { $_->id } @models ]);
    }

    return 1;
}

sub check_pse {
    my $self = shift;
    my $pse = shift;

    my $pse_id = $pse->id;

    $self->status_message('Check PSE for #' . $pse_id);

    my ($instrument_data_id)   = $pse->added_param('instrument_data_id');
    my ($instrument_data_type) = $pse->added_param('instrument_data_type');
    $instrument_data_type = lc $instrument_data_type;

    my @expected_types = ('sanger', 'solexa', '454', 'genotyper results');
    unless ( grep { $instrument_data_type eq $_ } @expected_types) {
        $self->error_message('encountered unkown instrument data type: ' . $instrument_data_type);
        return;
    }

    if ( $instrument_data_type eq 'sanger' ) {
        my $analyze_traces_pse = GSC::PSE::AnalyzeTraces->get($instrument_data_id);

        unless ( defined($analyze_traces_pse) ) {
            $self->error_message(
                'failed to fetch pse for sanger instrument data with id ' .
                $instrument_data_id .  ' and pse_id ' . $pse_id);
            return;
        }

        my $run_name = $analyze_traces_pse->run_name();

        unless ( defined($run_name) ) {
            $self->error_message(
                'failed to get a run_name for sanger instrument data with'
                . " id '$instrument_data_id' and pse_id '$pse_id'"
            );
            return;
        }

        $instrument_data_id = $run_name;
    }

    my $genome_instrument_data = Genome::InstrumentData->get(id => $instrument_data_id);

    unless ( $genome_instrument_data ) {
        $self->error_message(
            "Failed to get a Genome::InstrumentData ($instrument_data_type) via"
            . " id '$instrument_data_id'.  PSE_ID is '$pse_id'");
        return;
    }

    if ( $instrument_data_type eq 'solexa' ) {
        # solexa inst data nee to have the copy sequence file pse successful
        my $index_illumina = GSC::IndexIllumina->get($instrument_data_id);
        if ( not $index_illumina ) {
            $self->error_message('No index illumina for solexa instrument data '.$instrument_data_id);
            return;
        }
        if ( not $index_illumina->copy_sequence_files_confirmed_successfully ) {
            $self->error_message(
                'Solexa instrument data ('.$instrument_data_id.') does not have a successfully confirmed copy sequence files pse. This means it is not ready or may be corrupted.'
            );
            return;
        }

        if($genome_instrument_data->target_region_set_name) {
            my $fl = Genome::FeatureList->get(name => $genome_instrument_data->target_region_set_name);
            unless($fl) {
                $self->error_message('Failed to get a feature-list matching target region set name ' . $genome_instrument_data->target_region_set_name);
                return;
            }

            unless($fl->content_type) {
                $self->error_message('No content-type set on feature-list ' . $fl->name);
                return;
            } elsif ($fl->content_type eq 'roi') {
                $self->error_message('Unexpected "roi"-typed feature-list set as target region set name: ' . $fl->name);
                return;
            } elsif (!grep($_ eq $fl->content_type, 'exome', 'validation', 'targeted')) {
                $self->error_message('Unknown/unhandled content-type ' . $fl->content_type . ' on feature-list ' . $fl->name);
                return;
            }
        }
    }

    my ($subject_class_name)   = $pse->added_param('subject_class_name');
    my ($subject_id)           = $pse->added_param('subject_id');

    my @processing_profile_ids = $pse->added_param('processing_profile_id');

    #If specified, they must exist!
    if($subject_class_name or $subject_id or @processing_profile_ids) {
        my $subject = $subject_class_name->get($subject_id);
        unless (defined $subject) {
            $self->error_message(
                'failed to get a subject via subject_class_name'
                . " '$subject_class_name' with subject_id"
                . " '$subject_id'"
            );
            return;
        }
    }

    $self->status_message('Check PSE OK');

    return 1;
}

sub assign_instrument_data_to_models {
    my $self = shift;
    my $genome_instrument_data = shift;
    my $reference_sequence_build = shift;
    my @models = @_;

    my $instrument_data_id = $genome_instrument_data->id;

    # we don't want to (automagically) assign capture and non-capture data to the same model.
    if ( @models and $genome_instrument_data->can('target_region_set_name') ) {
        my $id_capture_target = $genome_instrument_data->target_region_set_name();

        if ($id_capture_target) {
            # keep only models with the specified capture target
            @models = grep($_->can('target_region_set_name') && $_->target_region_set_name eq $id_capture_target, @models);
        } else {
            # keep only models with NO capture target
            my %capture_model_ids = map { $_->model_id => 1 } Genome::Model::Input->get(
                model_id => [ map { $_->id } @models ],
                name => 'target_region_set_name',
            );
            @models = grep { not $capture_model_ids{$_->id} } @models;
        }
    }

    #we don't want to (automagically) assign rna seq and non-rna seq data to the same model.
    if (@models and $self->_is_rna_instrument_data($genome_instrument_data)){
        @models = grep($_->isa('Genome::Model::RnaSeq'), @models);
    }else{
        @models = grep(!($_->isa('Genome::Model::RnaSeq')), @models);
    }

    if($reference_sequence_build) {
        @models = grep($_->reference_sequence_build eq $reference_sequence_build, @models);
    }

    foreach my $model (@models) {
        my @existing_instrument_data = $model->input_for_instrument_data_id($instrument_data_id);

        if (@existing_instrument_data) {
            $self->warning_message(
                "instrument data '$instrument_data_id'" .
                ' already assigned to model ' . $model->id
            );

            my $existing_models = $self->_existing_models_with_existing_assignments;
            $existing_models->{$model->id} = $model;
        } else {
            my $assign =
            Genome::Model::Command::InstrumentData::Assign->create(
                instrument_data => [$genome_instrument_data],
                model           => $model,
            );

            unless ( $assign->execute ) {
                $self->error_message(
                    'Failed to execute instrument-data assign for '
                    . 'model '
                    . $model->id
                    . ' and instrument data '
                    . $instrument_data_id );
                return undef;
            }

            my $existing_models = $self->_existing_models_assigned_to;
            $existing_models->{$model->id} = $model;
        }
    }

    return @models;
}

sub create_default_models_and_assign_all_applicable_instrument_data {
    my $self = shift;
    my $genome_instrument_data = shift;
    my $subject = shift;
    my $processing_profile = shift;
    my $reference_sequence_build = shift;
    my $pse = shift;

    my @new_models;
    my @ref_align_models;

    my %model_params = (
        name                    => 'AQID-PLACE_HOLDER',
        user_name               => 'apipe-builder',
        subject_id              => $subject->id,
        subject_class_name      => $subject->class,
        processing_profile_id   => $processing_profile->id,
        auto_assign_inst_data   => 1,
    );

    if ($processing_profile->isa('Genome::ProcessingProfile::GenotypeMicroarray') ) {
        $model_params{auto_assign_inst_data} = 0;
    }

    if ( $reference_sequence_build ) {
        $model_params{reference_sequence_build} = $reference_sequence_build;
        unless( $processing_profile->isa('Genome::ProcessingProfile::RnaSeq')){
            my $dbsnp_build = Genome::Model::ImportedVariationList->dbsnp_build_for_reference($reference_sequence_build);
            $model_params{dbsnp_build} = $dbsnp_build if $dbsnp_build;
        }
        if ( $processing_profile->isa('Genome::ProcessingProfile::ReferenceAlignment')){
            my $annotation_build = Genome::Model::ImportedAnnotation->annotation_build_for_reference($reference_sequence_build);
            $model_params{annotation_reference_build} = $annotation_build if $annotation_build;
        }
    }

    my $regular_model = Genome::Model->create(%model_params);
    unless ( $regular_model ) {
        $self->error_message('Failed to create model with params: '.Dumper(\%model_params));
        return;
    }
    push @new_models, $regular_model;

    my $capture_target = eval{ $genome_instrument_data->target_region_set_name; };

    my $name = $regular_model->default_model_name(
        instrument_data => $genome_instrument_data,
        capture_target => $capture_target,
    );
    if ( not $name ) {
        $self->error_message('Failed to get model name for params: '.Dumper(\%model_params));
        for my $model ( @new_models ) { $model->delete; }
        return;
    }
    $regular_model->name($name);

    if ($regular_model->isa('Genome::Model::ReferenceAlignment')) {
        push @ref_align_models, $regular_model;
    }

    if ( $capture_target ) {
        my $roi_list;
        #FIXME This is a lame hack for these capture sets
        my %build36_to_37_rois = get_build36_to_37_rois();

        my $root_build37_ref_seq = $self->root_build37_ref_seq;

        if($reference_sequence_build and $reference_sequence_build->is_compatible_with($root_build37_ref_seq)
                and exists $build36_to_37_rois{$capture_target}) {
            $roi_list = $build36_to_37_rois{$capture_target};
        } else {
            $roi_list = $capture_target;
        }

        unless($self->assign_capture_inputs($regular_model, $capture_target, $roi_list)) {
            for my $model ( @new_models ) { $model->delete; }
            return;
        }

        #Also want to make a second model against a standard region of interest
        my $wuspace_model = Genome::Model->create(%model_params);
        unless ( $wuspace_model ) {
            $self->error_message('Failed to create wu-space model: '.Dumper(\%model_params));
            for my $model (@new_models) { $model->delete; }
            return;
        }
        push @new_models, $wuspace_model;

        my $wuspace_name = $wuspace_model->default_model_name(
            instrument_data => $genome_instrument_data,
            capture_target => $capture_target,
            roi => 'wu-space',
        );
        if ( not $wuspace_name ) {
            $self->error_message('Failed to get wu-space model name for params: '.Dumper(\%model_params));
            for my $model (@new_models) { $model->delete; }
            return;
        }
        $wuspace_model->name($wuspace_name);

        my $wuspace_roi_list;
        if($reference_sequence_build and $reference_sequence_build->is_compatible_with($root_build37_ref_seq)) {
            $wuspace_roi_list = 'NCBI-human.combined-annotation-58_37c_cds_exon_and_rna_merged_by_gene';
        } else {
            $wuspace_roi_list = 'NCBI-human.combined-annotation-54_36p_v2_CDSome_w_RNA';
        }

        unless($self->assign_capture_inputs($wuspace_model, $capture_target, $wuspace_roi_list)) {
            for my $model (@new_models) { $model->delete; }
            return;
        }

        #In addition, make a third model for TCGA against another standard ROI
        my $tcga_cds_model = Genome::Model->create(%model_params);
        unless ( $tcga_cds_model ) {
            $self->error_message('Failed to create tcga-cds model: ' . Dumper(\%model_params));
            for my $model (@new_models) { $model->delete; }
            return;
        }
        push @new_models, $tcga_cds_model;

        my $tcga_cds_name = $tcga_cds_model->default_model_name(
            instrument_data => $genome_instrument_data,
            capture_target => $capture_target,
            roi => 'tcga-cds',
        );
        if ( not $tcga_cds_name ) {
            $self->error_message('Failed to get tcga-cds model name for params: ' . Dumper(\%model_params));
            for my $model (@new_models) { $model->delete; }
            return;
        }
        $tcga_cds_model->name($tcga_cds_name);

        my $tcga_cds_roi_list = $self->tcga_roi_for_model($tcga_cds_model);

        unless($self->assign_capture_inputs($tcga_cds_model, $capture_target, $tcga_cds_roi_list)) {
            for my $model (@new_models) { $model->delete; }
            return;
        }

    }

    for my $m (@new_models) {
        my $assign =
        Genome::Model::Command::InstrumentData::Assign->create(
            model => $m,
            instrument_data => [$genome_instrument_data],
            include_imported => 1,
            force => 1,
        );

        unless ( $assign->execute ) {
            $self->error_message(
                'Failed to execute instrument-data assign for model '
                . $m->id . ' instrument data '.$genome_instrument_data->id );
            for my $model (@new_models) { $model->delete; }
            return;
        }

        unless($m->isa('Genome::Model::RnaSeq')){
            my $assign_all =
            Genome::Model::Command::InstrumentData::Assign->create(
                model => $m,
                all => 1,
            );

            unless ( $assign_all->execute ) {
                $self->error_message(
                    'Failed to execute instrument-data assign --all for model '
                    . $m->id );
                for my $model (@new_models) { $model->delete; }
                return;
            }
        }

        my @existing_instrument_data = $m->input_for_instrument_data($genome_instrument_data);
        unless (@existing_instrument_data) {
            $self->error_message(
                'instrument data ' . $genome_instrument_data->id . ' not assigned to model ????? (' . $m->id . ')'
            );
            for my $model (@new_models) { $model->delete; }
            return;
        }

        unless($m->isa('Genome::Model::RnaSeq') or $m->isa('Genome::Model::GenotypeMicroarray')){
            $self->add_model_to_default_modelgroups($m, $pse, $genome_instrument_data);
        }

        my $new_models = $self->_newly_created_models;
        $new_models->{$m->id} = $m;

        $pse->add_param('genome_model_id', $m->id);
    }

    # Now that they've had their instrument data assigned get_or_create_lane_qc_models
    # Based of the ref-align models so that alignment can shortcut
    push(@new_models , $self->create_default_qc_models(@ref_align_models));
    return @new_models;
}

sub get_build36_to_37_rois {
    return (
        'agilent sureselect exome version 2 broad refseq cds only' => 'agilent_sureselect_exome_version_2_broad_refseq_cds_only_hs37',
        'agilent sureselect exome version 2 broad' => 'agilent sureselect exome version 2 broad hg19 liftover',
        'hg18 nimblegen exome version 2' => 'hg19 nimblegen exome version 2',
        'NCBI-human.combined-annotation-54_36p_v2_CDSome_w_RNA' => 'NCBI-human.combined-annotation-54_36p_v2_CDSome_w_RNA_build36-build37_liftOver',
        'Freimer Pool of original (4k001L) plus gapfill (4k0026)' => 'Freimer-Boehnke capture-targets.set1_build37-fix1',
        '04110401 PoP32 EZ capture chip set'   => '04110401 PoP32 EZ capture chip set build37',
        'RT 49315 - AMD -- pool 1' => 'AMD-pool1-build37',
        '03110401 capture chip set' => '03110401 capture chip set - liftover_build37',
        'CleftPalate 03110402 capture chip set' => 'CleftPalate 03110402 capture chip set - liftover_build37',
    );
}

sub create_default_qc_models {
    my $self = shift;
    my @models = @_;
    my @new_models;
    for my $model (@models){
        next unless $model->type_name eq 'reference alignment';
        next unless $model->processing_profile_name =~ /^\w+\ \d+\ Default\ Reference\ Alignment/; # e.g. Feb 2011 Defaulte Reference Alignment

        my @lane_qc_models = $model->get_or_create_lane_qc_models;

        for my $lane_qc (@lane_qc_models) {
            next if $lane_qc->build_requested;
            next unless $lane_qc->build_needed;
            $lane_qc->build_requested(1);
            push @new_models, $lane_qc;
        }
    }

    return @new_models;
}

sub _find_or_create_mc16s_454_qc_model {
    my ($self, $instrument_data) = @_;

    $self->status_message("Find or create mc16s 454 qc model!");

    my $pp_id = $self->_default_mc16s_processing_profile_id;
    my $name = $instrument_data->run_name.'_r'.$instrument_data->region_number.'.prod-mc16s-qc';
    my $model = Genome::Model->get(
        name => $name,
        processing_profile_id => $pp_id,
    );
    if ( not $model ) {
        my $model = Genome::Model->create(
            name => $name,
            subject_id => 2863615589, # Human Metagenome
            subject_class_name => 'Genome::Taxon',
            processing_profile_id => $pp_id,
            auto_assign_inst_data => 0,
        );
        $model->add_instrument_data($instrument_data);
        my $new_models = $self->_newly_created_models;
        $new_models->{$model->id} = $model;
    }
    else {
        $model->add_instrument_data($instrument_data);
        my $assigned_to = $self->_existing_models_assigned_to;
        $assigned_to->{$model->id} = $model;
    }

    return 1;
}

sub assign_capture_inputs {
    my $self = shift;
    my $model = shift;
    my $target_region_set_name = shift;
    my $region_of_interest_set_name = shift;

    my $target_input = $model->add_input(
        name             => "target_region_set_name",
        value_class_name => "UR::Value",
        value_id         => $target_region_set_name
    );

    unless ( defined($target_input) ) {
        $self->error_message('Failed to set capture target input for model ' . $model->id);
        return;
    }

    my $roi_input = $model->add_input(
        name             => "region_of_interest_set_name",
        value_class_name => "UR::Value",
        value_id         => $region_of_interest_set_name
    );

    unless (defined($roi_input)) {
        $self->error_message('Failed to set region of instrument input for model ' . $model->id);
        return;
    }

    return 1;
}

sub add_model_to_default_modelgroups {
    my $self = shift;
    my $model = shift;
    my $pse = shift;
    my $instrument_data = shift;

    my $subject = $model->subject;


    my $source;
    if($subject->isa('Genome::Sample')) {
        $source = $subject->source;
    } elsif($subject->isa('Genome::Individual')) {
        $source = $subject;
    } elsif($subject->isa('Genome::Library')) {
        my $sample = $subject->sample;
        $source = $sample->source;
    } else {
        $self->error_message('Unhandled subject for model--not adding to common name model-groups');
    }

    my @groups = $self->_resolve_projects_and_work_orders($pse);
    my $pooled_sample_name = $self->_resolve_pooled_sample_name_for_instrument_data($instrument_data);
    if ($pooled_sample_name){
        if ($model->name =~ /\.wu-space$/) {
            $pooled_sample_name .= ".wu-space";
        }
        if ($model->name =~ /\.tcga-cds$/) {
            $pooled_sample_name .= ".tcga-cds";
        }
        push @groups, $pooled_sample_name;
    }

    unless($source) {
        $self->error_message('Failed to get source for subject.');
    } else {
        my $common_name = $source->common_name;
        if($common_name) {
            my ($source_grouping) = $common_name =~ /^([a-z]+)\d+$/i;
            push @groups, $source_grouping if $source_grouping;
        }
    }

    for my $group (@groups) {
        my $name;
        if (ref $group){#groups here can be research project objects, work order objects, pooled sample name or source grouping string
            $name = $group->can('name')?$group->name:$group->setup_name;
            if ($model->name =~ /\.wu-space$/) {
                $name .= ".wu-space";
            }
            if ($model->name =~ /\.tcga-cds$/) {
                $name .= ".tcga-cds";
            }
        }else{
            $name = $group;
        }

        my $project = Genome::Project->get(name => $name);

        # if $project_id gets set here it is used to create a new project
        # or to detect probable project renames
        my $project_id;
        if (ref($group) && $group->setup_name eq $name) {
            $project_id = $group->id;
        }

        if (!$project && $project_id) {
            # If we didn't get it by name try to get it by ID in case the name has been
            # changed since it was originally created, e.g. someone changed the name of a
            # work order. If we get it then we should fix the name. Observers automatically
            # trigger to update the corresponding Genome::ModelGroup.
            $project = Genome::Project->get($project_id);
            if ($project) {
                $project->name($name);
            }
        }

        unless($project) {
            my %params = ( name => $name );
            $params{id} = $project_id if $project_id;
            $project = Genome::Project->create(%params);
            unless($project) {
                die $self->error_message('Failed to create a default project: ' . $name);
            }
            if (ref $group){
                $project->add_part(entity => $group);
            }
        }

        my $model_group = Genome::ModelGroup->get(uuid => $project->id);
        unless ($model_group){
            die $self->error_message("No model group for ".$project->name);
        }

        $model_group->assign_models($model);
        #$project->add_part(entity => $model);
    }

    return 1;
}

sub _resolve_projects_and_work_orders{
    my $self = shift;
    my $pse = shift;

    my @names = ();
    my @work_orders;
    my ($instrument_data_id) = $pse->added_param('instrument_data_id');
    my $index_illumina = GSC::IndexIllumina->get($instrument_data_id);
    if($index_illumina){
        @work_orders = $index_illumina->get_work_orders;
    } else {
        @work_orders = $pse->get_inherited_assigned_directed_setups_filter_on('setup work order');
    }

    unless(scalar @work_orders) {
        $self->warning_message('No work order found for PSE ' . $pse->id);
    }

    my @projects = map($_->get_project, @work_orders);
    unless(scalar @projects) {
        $self->warning_message('No project found for PSE ' . $pse->id);
    }

    return grep {defined $_} (@projects, @work_orders);
}

sub _resolve_pooled_sample_name_for_instrument_data {
    my $self = shift;
    my $instrument_data = shift;

    return unless $instrument_data->can('index_sequence');
    my $index = $instrument_data->index_sequence;
    if($index) {
        my $instrument_data_class = $instrument_data->class;
        my $pooled_subset_name = $instrument_data->subset_name;
        $pooled_subset_name =~ s/${index}$/unknown/;

        my $pooled_instrument_data = $instrument_data_class->get(
            run_name => $instrument_data->run_name,
            subset_name => $pooled_subset_name,
            index_sequence => 'unknown',
        );
        return unless $pooled_instrument_data;

        my $sample = $pooled_instrument_data->sample;
        return unless $sample;

        return $sample->name;
    }

    return;
}

sub request_builds {
    my $self = shift;

    my $new_models = $self->_newly_created_models;
    my $assigned_to = $self->_existing_models_assigned_to;
    my %models_to_build;
    for my $model (values %$new_models) {
        #some models are explicitly not being built right away
        #but they might be picked up in other categories if instrument data is picked up in same AQID run
        next if defined $model->build_requested;
        $models_to_build{$model->id} = [$model, 'it is newly created'];
    }
    for my $model (values %$assigned_to) {
        next if exists $models_to_build{$model->id}; #already added above
        $models_to_build{$model->id} = [$model, 'it has been assigned to'];
    }

    $self->status_message("Finding models which need to build...");
    my $possibly_build = ($self->_existing_models_with_existing_assignments);
    for my $model (values %$possibly_build) {
        next if exists $models_to_build{$model->id}; #already added above
        my @builds = $model->builds;

        my $last_build = $builds[-1];

        unless(defined $last_build) {
            #no builds--can't possibly have built with all data
            my $reason = 'it has no builds';
            $self->status_message('Requesting build of model ' . $model->__display_name__ . " because $reason.");
            $models_to_build{$model->id} = [$model, $reason];
        } else {

            my %last_build_instdata = ( );

            my @last_build_inputs = $last_build->inputs;
            @last_build_inputs   = grep { $_->name eq 'instrument_data' } @last_build_inputs;
            %last_build_instdata = map  { $_->value_id => 1 }             @last_build_inputs;

            my @inputs = $model->instrument_data_inputs;
            my @missing_assignments_in_last_build = grep { not $last_build_instdata{$_->value_id} } @inputs;

            if (@missing_assignments_in_last_build) {
                my $reason = 'it does not have a final build with all assignments';
                $self->status_message("Requesting build of model " . $model->__display_name__ . " because $reason");
                $models_to_build{$model->id} = [$model, $reason];
            } else {
                $self->status_message("skipping rebuild of model " . $model->__display_name__ . " because all instrument data assignments are on the last build");
            }
        }
    }

    $self->status_message("Requesting builds...");

    MODEL: for my $model_and_reason (values %models_to_build) {
        my ($model, $reason) = @$model_and_reason;

        #TODO generalize via model->notify_input_build_success to make is_ready_to_build or the like
        if($model->isa('Genome::Model::SomaticValidation')) {
            if($model->tumor_sample and $model->normal_sample) {
                my @i = $model->instrument_data;

                my ($t, $n) = (0,0);
                for my $i (@i) {
                    if($i->sample eq $model->tumor_sample) { $t++; }
                    if($i->sample eq $model->normal_sample) { $n++; }
                }

                next MODEL unless ($t > 0 and $n > 0);
            }
        }

        #Will be picked up by next run of `genome model services build-queued-models`
        $model->build_requested(1, 'AQID: ' .$reason);
    }

    return 1;
}

sub add_processing_profiles_to_pses{
    my $self = shift;
    my @pses = @_;

    for my $pse (@pses){
        next if $pse->added_param('processing_profile_id'); #FIXME: THIS SHOULD ONLY BE USED DURING THE TRANSITION PERIOD WHILE OLD AQID IS IN USE
        my ($instrument_data_type) = $pse->added_param('instrument_data_type');
        my $instrument_data_id;
        if( $instrument_data_type =~ /sanger/i ) {
            #sanger data doesn't store the instrument_data_id directly
            my $at_pse = GSC::PSE::AnalyzeTraces->get($instrument_data_id);
            $instrument_data_id = $at_pse->run_name();
        }
        else {
            ($instrument_data_id) = $pse->added_param('instrument_data_id');
        }

        my $instrument_data = Genome::InstrumentData->get($instrument_data_id);
        unless ($instrument_data) {
            die $self->error_message('failed to get Genome::InstrumentData for instrument_data_id ' . $instrument_data_id . ' and instrument_data_type ' . $instrument_data_type);
        }

        eval {
            my @processing_profile_ids_to_add;
            my %reference_sequence_names_for_processing_profile_ids;

            my $sample_name        = $instrument_data->sample_name;
            my $sample_id          = $instrument_data->sample_id;
            my $subject_name       = $sample_name;
            my $subject_class_name = 'Genome::Sample';
            my $subject_id         = $sample_id;

            my $organism_sample = Genome::Sample->get($sample_id);

            unless (defined($organism_sample)) {
                $self->error_message('failed to get a Genome::Sample for id ' . $instrument_data_id);
                die $self->error_message;
            }

            my $taxon = get_organism_taxon($organism_sample);;

            unless (defined($taxon)) {
                $self->error_message('failed to get taxon via Genome::Taxon for id ' . $instrument_data_id);
                die $self->error_message;
            }

            if ($instrument_data_type =~ /454/) {
                my @unknown_work_orders = $self->_is_unknown_454_pipeline($pse);
                if (@unknown_work_orders) {

                    my $pipeline_string  = $self->_pipeline_prettyprint(@unknown_work_orders);
                    my $workorder_string = $self->_workorder_prettyprint(@unknown_work_orders);

                    my $sender = Mail::Sender->new({
                            smtp    => 'gscsmtp.wustl.edu',
                            from    => 'Apipe <apipe-builder@genome.wustl.edu>'
                        });
                    $sender->MailMsg( {

                            to      => 'Analysis Pipeline <apipebulk@genome.wustl.edu>, Apipe Builder <apipe-builder@genome.wustl.edu>',
                            cc      => 'Scott Smith <ssmith@genome.wustl.edu>, Jim Eldred <jeldred@genome.wustl.edu>, Justin Lolofie <jlolofie@genome.wustl.edu>, Thomas Mooney <tmooney@genome.wustl.edu>',
                            subject => "ecountered unknown workorder pipeline '$pipeline_string' in QIDFGM PSE",
                            msg     => 'no PP assigned to 454 data ' . $instrument_data_id . ' please check out it (see AQID)' . "\n\nWork Order Information:\n$workorder_string",
                        });

                    $self->error_message("unknown 454 workorder pipeline '$pipeline_string' encountered");
                    die $self->error_message;
                }

                if($self->_is_rna($instrument_data)){
                    push @processing_profile_ids_to_add, $self->_default_rna_seq_processing_profile_id;
                }

                if ($self->_is_454_16s($pse)) {
                    push @processing_profile_ids_to_add, $self->_default_mc16s_processing_profile_id;
                }
            }
            elsif ($instrument_data_type =~ /sanger/i) {
                # this is only meant to work with 16s sanger instrument data at present
                push @processing_profile_ids_to_add, 2591277; # MC16s-WashU-Sanger-RDP2.2-ts6 was amplicon assembly 2067049
            }
            elsif ($instrument_data_type eq 'genotyper results' ) {
                # Genotype Microarry PP as of 2011jan25
                # ID        NAME              INPUT_FORMAT   INSTRUMENT_TYPE
                # --        ----              ------------   ---------------
                # 2166945   illumina/wugc     wugc           illumina
                # 2166946   affymetrix/wugc   wugc           affymetrix
                # 2186707   unknown/wugc      wugc           unknown
                # 2575175   infinium/wugc     wugc           infinium
                my $sequencing_platform = $instrument_data->sequencing_platform;
                my $pp = Genome::ProcessingProfile::GenotypeMicroarray->get(
                    instrument_type => $sequencing_platform,
                    input_format => 'wugc',
                );
                if ( not $pp ) {
                    my $msg = "Unknown platform ($sequencing_platform) for genotyper result ($instrument_data_id)";

                    my $sender = Mail::Sender->new({
                            smtp    => 'gscsmtp.wustl.edu',
                            from    => 'Apipe <apipe-builder@genome.wustl.edu>'
                        });
                    $sender->MailMsg( {

                            to      => 'Analysis Pipeline <apipebulk@genome.wustl.edu>, Apipe Builder <apipe-builder@genome.wustl.edu>',
                            cc      => 'Scott Smith <ssmith@genome.wustl.edu>, Jim Eldred <jeldred@genome.wustl.edu>, Eddie Belter <ebelter@genome.wustl.edu>, Thomas Mooney <tmooney@genome.wustl.edu>',
                            subject => "QIDFGM PSE ERROR: $msg",
                            msg     => "Could not find a genotype microarray processing profile for genotyper results instrument data ($instrument_data_id) sequencing platform ($sequencing_platform) in QIDFGM PSE (see AQID)".$self->id
                        });

                    die $self->error_message($msg);
                }
                # build w/ 36 and 37
                # push the pp id 2X, add import ref seq build for both
                push @processing_profile_ids_to_add, $pp->id, $pp->id;
                for my $name (qw/ NCBI-human-build36 GRCh37-lite-build37/) {
                    my $imported_reference_sequence = Genome::Model::Build::ImportedReferenceSequence->get_by_name($name);
                    Carp::confess("No imported reference sequence build for $name") if not $imported_reference_sequence;
                    $pse->add_reference_sequence_build_param_for_processing_profile($pp, $imported_reference_sequence);
                }
            }
            elsif ($instrument_data_type =~ /solexa/i) {
                if($instrument_data->target_region_set_name and Genome::FeatureList->get(name => $instrument_data->target_region_set_name)->content_type eq 'validation') {
                     #Do not create ref-align models--will try to assign to existing SomaticValidation models.
                } elsif ($taxon->species_latin_name =~ /homo sapiens/i) {
                    if ($self->_is_pcgp($pse)) {
                        my $individual = $organism_sample->patient;
                        my $pp_id = '2644306';
                        my $common_name = $individual ? $individual->common_name : '';

                        push @processing_profile_ids_to_add, $pp_id;
                        $reference_sequence_names_for_processing_profile_ids{$pp_id} = 'GRCh37-lite-build37';
                    }
                    elsif ($self->_is_rna($instrument_data)){
                        if($instrument_data->is_paired_end){
                            my $pp_id = $self->_default_rna_seq_processing_profile_id;
                            push @processing_profile_ids_to_add, $pp_id;
                            $reference_sequence_names_for_processing_profile_ids{$pp_id} = 'GRCh37-lite-build37';
                        }
                    }
                    else {
                        my $pp_id = '2635769';
                        push @processing_profile_ids_to_add, $pp_id;

                        # NOTE: this is the _fixed_ build 37 with a correct external URI
                        $reference_sequence_names_for_processing_profile_ids{$pp_id} = 'GRCh37-lite-build37';
                    }
                }
                elsif ($taxon->species_latin_name =~ /mus musculus/i){
                    my $pp_id = 2635769;
                    push @processing_profile_ids_to_add, $pp_id;
                    $reference_sequence_names_for_processing_profile_ids{$pp_id} = 'UCSC-mouse-buildmm9'
                }
                elsif ($taxon->domain =~ /bacteria/i) {
                    my $pp_id = $self->_default_de_novo_assembly_bacterial_processing_profile_id;
                    push @processing_profile_ids_to_add, $pp_id;
                }
                elsif ( my $index_illumina = GSC::IndexIllumina->get( $instrument_data_id ) ) {
                    for my $research_project ( $index_illumina->get_research_projects ) { #research project
                        my $genome_project = Genome::Project->get( id => $research_project->setup_id );
                        if ( not $genome_project ) {
                            Carp::confess('No genome project found for research project setup_id: '.$research_project->setup_id );
                        }
                        my @pp_parts = $genome_project->parts( label => 'default_processing_profiles' );
                        for my $part ( @pp_parts ) {
                            push @processing_profile_ids_to_add, $part->entity_id;
                        }
                        #if ( $project->id == 2269562 ) { # HMP Centers Grant Reference Genomes WU Strain Collection
                        #    my $pp_id = $self->_default_de_novo_assembly_bacterial_processing_profile_id;
                        #    push @processing_profile_ids_to_add, $pp_id;
                        #    last;
                        #}
                    }
                }
            }

            $self->_verify_parameter_lists(\@processing_profile_ids_to_add, \%reference_sequence_names_for_processing_profile_ids);

            #all verification is complete--now go through and set the parameters
            $pse->add_param('sample_name',  $sample_name);
            $pse->add_param('subject_class_name', $subject_class_name);
            $pse->add_param('subject_id', $subject_id);

            # ask each if they work with this type of instrument data?
            PP:         for my $pp_id (@processing_profile_ids_to_add) {
                my $pp = Genome::ProcessingProfile->get($pp_id);
                if ($instrument_data_type =~ /454/) {
                    if ($pp->can('instrument_data_is_applicable')) {
                        unless ($pp->instrument_data_is_applicable($instrument_data_type,$instrument_data_id,$subject_name)) {
                            next PP;
                        }
                    }
                }
                $pse->add_param("processing_profile_id", $pp->id);
            }

            for my $pp_id (keys %reference_sequence_names_for_processing_profile_ids) {
                my $imported_reference_sequence_name = $reference_sequence_names_for_processing_profile_ids{$pp_id};

                my $pp = Genome::ProcessingProfile->get($pp_id);
                my $imported_reference_sequence = Genome::Model::Build::ImportedReferenceSequence->get_by_name($imported_reference_sequence_name);
                $pse->add_reference_sequence_build_param_for_processing_profile($pp, $imported_reference_sequence);
            }
        };
        if($@){
            #something went horribly wrong.  do something about it.
            $self->warning_message("PSE " . $pse->pse_id . " failed: $@");
        }
    }
}

sub _verify_parameter_lists {
    my $self = shift;
    my $processing_profile_ids_to_add = shift;
    my $reference_sequence_names_for_processing_profile_ids = shift;

    #Just go through the lists and check that the IDs point to real objects
    for my $pp_id (@$processing_profile_ids_to_add) {
        my $pp = Genome::ProcessingProfile->get($pp_id);
        unless($pp) {
            unless (defined($pp)) {
                $self->error_message("failed to get a Genome::ProcessingProfile using id '$pp_id'");
                die $self->error_message;
            }
        }
    }

    for my $pp_id (keys %$reference_sequence_names_for_processing_profile_ids) {
        my $pp = Genome::ProcessingProfile->get($pp_id);
        unless($pp) {
            unless (defined($pp)) {
                $self->error_message("failed to get a Genome::ProcessingProfile using id '$pp_id'");
                die $self->error_message;
            }
        }

        my $imported_reference_sequence_name = $reference_sequence_names_for_processing_profile_ids->{$pp_id};
        my $imported_reference_sequence = Genome::Model::Build::ImportedReferenceSequence->get_by_name($imported_reference_sequence_name);
        unless(defined($imported_reference_sequence)) {
            $self->error_message('failed to get reference sequence build for ' . $imported_reference_sequence_name . '.');
            die $self->error_message;
        }
    }

    return 1;
}

sub _is_454_16s {
    my $self = shift;
    my $pse = shift;

    my @work_orders;

    my ($instrument_data_id) = $pse->added_param('instrument_data_id');
    my $index_illumina = GSC::IndexIllumina->get($instrument_data_id);
    if($index_illumina){
        @work_orders = $index_illumina->get_work_orders;
    } else{
        @work_orders = $pse->get_inherited_assigned_directed_setups_filter_on('setup work order');
    }

    foreach my $work_order (@work_orders) {
        my $pipeline_string = $work_order->pipeline();
        unless (defined($pipeline_string)) { next; }

        my @pipelines = split(',', $pipeline_string);
        for my $pipeline (@pipelines) {
            if (exists($known_454_16s_pipelines{$pipeline})) {
                return 1;
            }
        }
    }

    return 0;
}

sub _is_unknown_454_pipeline {
    my $self = shift;
    my $pse = shift;

    my @work_orders;

    my ($instrument_data_id) = $pse->added_param('instrument_data_id');
    my $index_illumina = GSC::IndexIllumina->get($instrument_data_id);
    if($index_illumina){
        @work_orders = $index_illumina->get_work_orders;
    } else{
        @work_orders = $pse->get_inherited_assigned_directed_setups_filter_on('setup work order');
    }

    unless (@work_orders > 0) {
        $self->error_message('454 instrument_data ' . $pse->added_param('instrument_data_id') . ' has no work order(s)');
        die;
    }

    my $pipelines_found = 0;

    my @workorders_with_unknown_pipelines;

    foreach my $work_order (@work_orders) {
        my $pipeline_string = $work_order->pipeline();
        unless (defined($pipeline_string)) { next; }

        my @pipelines = split(',', $pipeline_string);
        for my $pipeline (@pipelines) {
            if (not exists($known_454_pipelines{$pipeline})) {
                push @workorders_with_unknown_pipelines, $work_order;
            }
        }
    }

    return @workorders_with_unknown_pipelines; #return the workorder so we can construct nice error messages
}

sub _pipeline_prettyprint {
    my $self = shift;
    my @work_orders = @_;
    return join("<>", map($_->pipeline, @work_orders));
}

sub _workorder_prettyprint {
    my $self = shift;
    my @work_orders = @_;

    my $detailed_string = "";

    for my $work_order (@work_orders){
        $detailed_string .= join("\n", map($_ .": " .$work_order->$_, (qw/ id pipeline facilitator_unix_login setup_status /)));
        $detailed_string .= "\n\n";
    }

    return $detailed_string;
}

sub _is_pcgp {
    my $self = shift;
    my $pse = shift;

    my ($instrument_data_id) = $pse->added_param('instrument_data_id');
    my $index_illumina = GSC::IndexIllumina->get($instrument_data_id);
    my @work_orders = $index_illumina->get_work_orders;

    foreach my $work_order (@work_orders) {
        my $project_id = $work_order->project_id;

        if ( grep($project_id eq $_, (2230523, 2230525, 2259255, 2342358)) ) {
            return 1;
        }
    }

    return 0;
}

sub _is_rna {
    my ($self, $instrument_data) = @_;

    my $sample = $instrument_data->sample;
    if(grep($sample->sample_type eq $_, ('rna', 'cdna', 'total rna', 'cdna library', 'mrna'))) {
        return 1;
    }
    return 0;
}

sub _is_rna_instrument_data {
    my $self = shift;
    my $instrument_data = shift;
    my $sample = $instrument_data->sample;
    if(grep($sample->sample_type eq $_, ('rna', 'cdna', 'total rna', 'cdna library', 'mrna'))) {
        return 1;
    }
    return 0;
}

1;
