
package Genome::Model::ReferenceAlignment;

#:eclark 11/18/2009 Code review.

# I'm not sure that we need to have all these via properties.  Does it really gain us that much code clarity?
# Some of the other properties seem generic enough to be part of Genome::Model, not this subclass.
# The entire set of _calculcute* methods could be refactored away.
# Several deprecated/todo comments scattered in the code below that should either be removed or implemented.
# Most of the methods at the bottom are for reading/writing of a gold_snp_file, this should be implemented as
# part of Genome/Utility/IO

use strict;
use warnings;

use Genome;
use Term::ANSIColor;
use File::Path;
use File::Basename;
use IO::File;
use Sort::Naturally;
use Data::Dumper;

my %DEPENDENT_PROPERTIES = (
    # dbsnp_build and annotation depend on reference_sequence_build
    'reference_sequence_build' => [
        'dbsnp_build',
        'annotation_reference_build',
    ],
);

class Genome::Model::ReferenceAlignment {
    is => 'Genome::Model',
    has => [
        align_dist_threshold         => { via => 'processing_profile'},
        dna_type                     => { via => 'processing_profile'},
        picard_version               => { via => 'processing_profile'},
        samtools_version             => { via => 'processing_profile'},
        merger_name                  => { via => 'processing_profile'},
        merger_version               => { via => 'processing_profile'},
        merger_params                => { via => 'processing_profile'},
        duplication_handler_name     => { via => 'processing_profile'},
        duplication_handler_version  => { via => 'processing_profile'},
        duplication_handler_params   => { via => 'processing_profile'},
        snv_detection_strategy       => { via => 'processing_profile'},
        indel_detection_strategy     => { via => 'processing_profile'},
        sv_detection_strategy        => { via => 'processing_profile'},
        cnv_detection_strategy       => { via => 'processing_profile'},
        transcript_variant_annotator_version => { via => 'processing_profile' },
        transcript_variant_annotator_filter => { via => 'processing_profile' },
        transcript_variant_annotator_accept_reference_IUB_codes => {via => 'processing_profile'},
        multi_read_fragment_strategy => { via => 'processing_profile'},
        prior_ref_seq                => { via => 'processing_profile'},
        read_aligner_name => {
            calculate_from => 'processing_profile',
            calculate => q|
                my $read_aligner_name = $processing_profile->read_aligner_name;
                if ($read_aligner_name =~ /^maq/) {
                    return 'maq';
                }
                return $read_aligner_name;
            |,
        },
        read_aligner_version         => { via => 'processing_profile'},
        read_aligner_params          => { via => 'processing_profile'},
        read_trimmer_name            => { via => 'processing_profile'},
        read_trimmer_version         => { via => 'processing_profile'},
        read_trimmer_params          => { via => 'processing_profile'},
        force_fragment               => { via => 'processing_profile'},
        read_calibrator_name         => { via => 'processing_profile'},
        read_calibrator_params       => { via => 'processing_profile'},
        reference_sequence_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'reference_sequence_build', value_class_name => 'Genome::Model::Build::ImportedReferenceSequence' ],
            is_many => 0,
            is_mutable => 1, # TODO: make this non-optional once backfilling is complete and reference placeholder is deleted
            is_optional => 1,
            doc => 'reference sequence to align against'
        },
        reference_sequence_build => {
            is => 'Genome::Model::Build::ImportedReferenceSequence',
            id_by => 'reference_sequence_build_id',
        },
        dbsnp_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'dbsnp_build', value_class_name => 'Genome::Model::Build::ImportedVariationList' ],
            is_many => 0,
            is_mutable => 1,
            is_optional => 1,
            doc => 'dbsnp build to compare against'
        },
        dbsnp_build => {
            is => 'Genome::Model::Build::ImportedVariationList',
            id_by => 'dbsnp_build_id',
        },
        dbsnp_model => {
            via => 'dbsnp_build',
            to => 'model',
        },
        genotype_microarray_model_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'genotype_microarray', 'value_class_name' => 'Genome::Model::GenotypeMicroarray', ],
            is_mutable => 1,
            is_optional => 1,
            doc => 'Genotype Microarray model used for QC and Gold SNP Concordance report',
        },
        genotype_microarray_model => {
            is => 'Genome::Model::GenotypeMicroarray',
            id_by => 'genotype_microarray_model_id',
        },
        annotation_reference_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'annotation_reference_build', 'value_class_name' => 'Genome::Model::Build::ImportedAnnotation' ],
            is_many => 0,
            is_mutable => 1,
            is_optional => 1,
            doc => 'The reference build used for variant annotation',
        },
        annotation_reference_build => {
            is => 'Genome::Model::Build::ImportedAnnotation',
            id_by => 'annotation_reference_build_id',
        },
        reference_sequence_name      => { via => 'reference_sequence_build', to => 'name' },
        annotation_reference_name    => { via => 'annotation_reference_build', to => 'name' },
        coverage_stats_params        => { via => 'processing_profile'},
        assignment_events => {
            is => 'Genome::Model::Event::Build::ReferenceAlignment::AssignRun',
            is_many => 1,
            reverse_id_by => 'model',
            doc => 'each case of an instrument datum being assigned to the model',
        },
        alignment_events => {
            is => 'Genome::Model::Event::Build::ReferenceAlignment::AlignReads',
            is_many => 1,
            reverse_id_by => 'model',
            doc => 'each case of a read set being aligned to the model\'s reference sequence(s), possibly including multiple actual aligner executions',
        },
        #this is to get the SNP statistics...
        filter_variation_events => {
            is => 'Genome::Model::Event::Build::ReferenceAlignment::FilterVariations',
            is_many => 1,
            reverse_id_by => 'model',
            doc => 'each case of variations filtered per chromosome',
        },
        alignment_file_paths => { via => 'alignment_events' },
        has_all_alignment_metrics => { via => 'alignment_events', to => 'has_all_metrics' },
        has_all_filter_variation_metrics => { via => 'filter_variation_events', to => 'has_all_metrics' },
        build_events  => {
            is => 'Genome::Model::Event::Build',
            reverse_id_by => 'model',
            is_many => 1,
            where => [
                parent_event_id => undef,
            ]
        },
        latest_build_event => {
            calculate_from => ['build_event_arrayref'],
            calculate => q|
                my @e = sort { $a->id cmp $b->id } @$build_event_arrayref;
                my $e = $e[-1];
                return $e;
            |,
        },
        running_build_event => {
            calculate_from => ['latest_build_event'],
            calculate => q|
                # TODO: we don't currently have this event complete when child events are done.
                #return if $latest_build_event->event_status('Succeeded');
                return $latest_build_event;
            |,
        },
        filter_ruleset_name   => { via => 'processing_profile' },
        filter_ruleset_params => { via => 'processing_profile' },
        target_region_set_name => {
            is_many => 1, is_mutable => 1, is => 'Text', via => 'inputs', to => 'value_id', 
            where => [ name => 'target_region_set_name', value_class_name => 'UR::Value' ]
        },
    ],
    doc => 'A genome model produced by aligning DNA reads to a reference sequence.'
};

sub create {
    my $class = shift;

    # This is a temporary hack to allow annotation_reference_build (currently calculated) to be
    # passed in as an object. Once the transition to using model inputs for this parameter vs
    # processing profile params, annotation_reference_build can work like reference_sequence_build
    # and this code can go away.
    my @args = @_;
    if (scalar(@_) % 2 == 0) {
        my %args = @args;
        if (defined $args{annotation_reference_build}) {
            $args{annotation_reference_build_id} = (delete $args{annotation_reference_build})->id;
            @args = %args;
        }
    }

    my $self = $class->SUPER::create(@args)
        or return;

    unless ( $self->reference_sequence_build ) {
        $self->error_message("Missing needed reference sequence build during reference alignment model creation.");
        $self->delete;
        return;
    }

    unless ($self->genotype_microarray_model_id) {
        my $genotype_model = $self->default_genotype_model;
        if ($genotype_model) {
            $self->genotype_microarray_model_id($genotype_model->id);
        }
    }

    if ($self->read_aligner_name and $self->read_aligner_name eq 'newbler') {
        my $new_mapping = Genome::Model::Tools::454::Newbler::NewMapping->create(
            dir => $self->alignments_directory,
        );
        unless ($self->new_mapping) {
            $self->error_message('Could not setup newMapping for newbler in directory '. $self->alignments_directory);
            return;
        }
        my @fasta_files = grep {$_ !~ /all_sequences/} $self->get_subreference_paths(reference_extension => 'fasta');
        my $set_ref = Genome::Model::Tools::454::Newbler::SetRef->create(
                                                                    dir => $self->alignments_directory,
                                                                    reference_fasta_files => \@fasta_files,
                                                                );
        unless ($set_ref->execute) {
            $self->error_message('Could not set refrence setRef for newbler in directory '. $self->alignments_directory);
            return;
        }
    }
    return $self;
}

sub libraries {
    my $self = shift;
    my %libraries = map {$_->library_name => 1} $self->instrument_data;
    my @distinct_libraries = keys %libraries;
    if ($self->name =~ /v0b/) {
        warn "removing any *d libraries from v0b models.  temp hack for AML v0b models.";
        @distinct_libraries = grep { $_ !~ /d$/ } @distinct_libraries;
    }
    return @distinct_libraries;
}

sub _calculate_library_count {
    my $self = shift;
    return scalar($self->libraries);
}

sub complete_build_directory {
    my $self=shift;
    if (defined $self->last_complete_build) {
        return $self->last_complete_build->data_directory;
    }
    else
    {
        return;
    }
}

sub run_names {
    my $self = shift;
    my %distinct_run_names = map { $_->run_name => 1}  $self->instrument_data;
    my @distinct_run_names = keys %distinct_run_names;
    return @distinct_run_names;
}

sub _calculate_run_count {
    my $self = shift;
    return scalar($self->run_names);
}

sub region_of_interest_set {
    my $self = shift;

    my $name = $self->region_of_interest_set_name;
    return unless $name;
    my $roi_set = Genome::FeatureList->get(name => $name);
    unless ($roi_set) {
        die('Failed to find feature-list with name: '. $name);
    }
    return $roi_set;
}

sub accumulated_alignments_directory {
    my $self = shift;
    return $self->complete_build_directory . '/alignments';
}

sub is_eliminate_all_duplicates {
    my $self = shift;

    if ($self->multi_read_fragment_strategy and
        $self->multi_read_fragment_strategy eq 'EliminateAllDuplicates') {
        1;
    } else {
        0;
    }
}

sub is_capture {
    my $self = shift;
    if (defined $self->target_region_set_name) {
        return 1;
    }
    return 0;
}

sub is_lane_qc {
    my $self = shift;
    my $pp = $self->processing_profile;
    if ($pp->append_event_steps && $pp->append_event_steps =~ /LaneQc/) {
        return 1;
    }
    return 0;
}

# Determines the correct genotype model to use via the official genotype data assigned to the subject
sub default_genotype_model {
    my $self = shift;
    my $sample = $self->subject;
    return unless $sample->isa('Genome::Sample');

    my @genotype_models = sort { $a->id <=> $b->id } $sample->default_genotype_models;
    return unless @genotype_models;

    @genotype_models = grep { $_->reference_sequence_build->is_compatible_with($self->reference_sequence_build) } @genotype_models;
    return unless @genotype_models;


    my $chosen_genotype_model;
    if (@genotype_models > 1) {
        my $message = "Found multiple compatible genotype models for sample " . $sample->id . " and reference alignment model " . $self->id;
        my @used_genotype_models = grep { $_->is_used_as_model_or_build_input or $_->builds_are_used_as_model_or_build_input } @genotype_models;
        if (@used_genotype_models) {
            $self->warning_message($message . ", choosing the most recent previously-used model.");
            $chosen_genotype_model = $used_genotype_models[-1];
        } else {
            $self->warning_message($message . ", choosing most recent model.");
            $chosen_genotype_model = $genotype_models[-1];
        }
    }

    return $chosen_genotype_model;
}

sub build_subclass_name {
    return 'reference alignment';
}

sub dependent_properties {
    my ($self, $property_name) = @_;
    return @{$DEPENDENT_PROPERTIES{$property_name}} if exists $DEPENDENT_PROPERTIES{$property_name};
    return;
}

sub check_for_updates {
    my $self = shift;
    $self->check_and_update_genotype_input;
    return 1;
}

sub check_and_update_genotype_input {
    my $self = shift;
    my $default_genotype_model = $self->default_genotype_model;
    return 1 unless $default_genotype_model;

    if (defined $self->genotype_microarray_model_id and $self->genotype_microarray_model_id ne $default_genotype_model->id) {
        if (defined $self->user_name and $self->user_name eq 'apipe-builder') {
            $self->warning_message("Sample " . $self->subject_id . " points to genotype model " . $default_genotype_model->id .
                ", which disagrees with the genotype model input of this model (" . $self->genotype_microarray_model_id .
                "), overwriting!");
            $self->genotype_microarray_model_id($default_genotype_model->id);
        }
    }
    elsif (not defined $self->genotype_microarray_model_id) {
        $self->genotype_microarray_model_id($default_genotype_model->id);
    }

    return 1;
}


sub default_qc_model_name_for_instrument_data {
    my $self = shift;
    my $instrument_data = shift;

    my $subset_name = $instrument_data->subset_name || 'unknown-subset';
    my $run_name_method = $instrument_data->can('short_name') ? 'short_name' : 'run_name';
    my $run_name = $instrument_data->$run_name_method || 'unknown-run';
    my $lane_name = $run_name . '.' . $subset_name;
    my $model_name = $lane_name . '.prod-qc';

    if ($instrument_data->target_region_set_name) {
        $model_name .= '.capture.' . $instrument_data->target_region_set_name;
    }

    return $model_name;
}


sub qc_processing_profile_id {
    my $self = shift;

    my %qc_pp_id = ( # Map alignment processing profile to lane QC version
        2574937 => '2597031', # bwa 0.5.5 untrimmed and samtools r453 and picard_align 1.17 and picard_dedup 1.29
        2580856 => '2581081', # Feb 2011 Default Reference Alignment
        2582616 => '2589389', # old february 2011 default genome and exome with build37 annotation
        2580859 => '2589388', # Feb 2011 Default Reference Alignment (PCGP)
        2586039 => '2589390', # Mar 2011 Default Reference Alignment (PCGP Untrimmed)
    );

    return $qc_pp_id{ $self->processing_profile_id };
}


sub get_or_create_lane_qc_models {
    my $self = shift;

    my $subject = $self->subject;

    unless ($subject->default_genotype_data_id) {
        $self->warning_message("Sample is missing default_genotype_data_id cannot create lane QC model.");
        return;
    }

    my $qc_pp_id = $self->qc_processing_profile_id;
    unless ($qc_pp_id) {
        $self->warning_message("Unable to determine which processing profile to use for lane QC model.");
        return;
    }

    my @lane_qc_models;
    my @instrument_data = sort { $a->run_name . $a->subset_name cmp $b->run_name . $b->subset_name } $self->instrument_data;
    for my $instrument_data (@instrument_data) {
        my $lane_qc_model_name = $self->default_qc_model_name_for_instrument_data($instrument_data);

        my $existing_model = Genome::Model->get(name => $lane_qc_model_name);
        if ($existing_model) {
            if ($existing_model->genotype_microarray_model_id) {
                $self->status_message("Default lane QC model " . $existing_model->__display_name__ . " already exists.");
            }
            else {
                $self->status_message("New build requested for lane QC model " . $existing_model->__display_name__ . " because it is missing the genotype_microarray input.");
                $existing_model->build_requested(1);
            }
            push @lane_qc_models, $existing_model;
            next;
        }

        my $qc_model = Genome::Model::ReferenceAlignment->create(
            name => $lane_qc_model_name,
            instrument_data => [$instrument_data],
            subject_id => $self->subject_id,
            subject_class_name => $self->subject_class_name,
            processing_profile_id => $qc_pp_id,
            auto_assign_inst_data => 0,
            auto_build_alignments => 0,
            build_requested => 0,
            reference_sequence_build => $self->reference_sequence_build,
            dbsnp_build => $self->dbsnp_build,
        );
        unless ($qc_model) {
            $self->error_message("Could not create lane qc model for instrument data " . $instrument_data->id);
            next;
        }

        push @lane_qc_models, $qc_model;
    }

    if (@lane_qc_models == @instrument_data) {
        return @lane_qc_models;
    }
    return;
}

sub latest_build_id {
    my $self = shift;
    my $build = $self->latest_build;
    unless ($build) { return; }
    return $build->id;
}

sub latest_build_bam_file {
    my $self = shift;

    my $build = $self->latest_build;
    unless ($build) { return; }

    my @events = $build->the_events;
    unless (@events) { return; }

    my ($merge) = grep {($_->class eq 'Genome::Model::Event::Build::ReferenceAlignment::DeduplicateLibraries::Picard') || ($_->class eq 'Genome::Model::Event::Build::ReferenceAlignment::MergeAlignments')} @events;
    unless ($merge) { return; }

    unless ($merge->event_status eq 'Succeeded') {
        #print STDERR 'Merge not Succeeded: '. $build->id ."\n";
        return;
    }
    my $bam_file = $build->whole_rmdup_bam_file;
    return $bam_file;
}

1;
