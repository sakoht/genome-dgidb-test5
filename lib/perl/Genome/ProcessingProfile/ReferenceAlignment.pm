package Genome::ProcessingProfile::ReferenceAlignment;

use strict;
use warnings;

use Genome;

class Genome::ProcessingProfile::ReferenceAlignment {
    is => 'Genome::ProcessingProfile::Staged',
    is_abstract => 1,
    subclassify_by => 'subclass_name',
    has => [
        subclass_name => { is_mutable => 0,
                           calculate_from => ['sequencing_platform'],
                           calculate => sub {
                                            my($sequencing_platform) = @_;
                                            Carp::confess "No sequencing platform given to resolve subclass name" unless $sequencing_platform;
                                            return 'Genome::ProcessingProfile::ReferenceAlignment::'.Genome::Utility::Text::string_to_camel_case($sequencing_platform);
                                          }
                         },
    ],

    has_param => [
        sequencing_platform => {
            doc => 'The sequencing platform from whence the model data was generated',
            valid_values => ['454', 'solexa', '3730'],
        },
        dna_type => {
            doc => 'the type of dna used in the reads for this model',
            valid_values => ['genomic dna', 'cdna']
        },
        snv_detector_name => {
            doc => 'Name of the snv detector',
            is_optional => 1,
        },
        snv_detector_version => {
            doc => 'version of the snv detector',
            is_optional => 1,
        },
        snv_detector_params => {
            doc => 'command line args used for the snv detector',  
            is_optional => 1,
        },
        indel_detector_name => {
            doc => 'Name of the indel detector',
            is_optional => 1,
        },
        indel_detector_version => {
            doc => 'version of the indel detector',
            is_optional => 1,
        },
        indel_detector_params => {
            doc => 'command line args used for the indel detector',  
            is_optional => 1,
        },
        genotyper_name => {
            doc => 'name of the genotyper for this model... deprecated',
            is_optional => 1,
        },
        genotyper_version => {
            doc => 'version of the genotyper for this model... deprecated',
            is_optional => 1,
        },
        genotyper_params => {
            doc => 'command line args used for the genotyper... deprecated',
            is_optional => 1,
        },
        indel_finder_name => {
            doc => 'name of the indel finder for this model... deprecated',
            is_optional => 1,
        },
        indel_finder_version => {
            doc => 'version of the indel finder for this model... deprecated',
            is_optional => 1,
        },
        indel_finder_params => {
            doc => 'command line args for the indel finder... deprecated',
            is_optional => 1,
        },
        variant_filter => {
            doc => 'variant filter type: VarFilter or SnpFilter... deprecated',
            is_optional => 1,
        },
        multi_read_fragment_strategy => {
            doc => '',
            is_optional => 1,
        },
        merge_software => {
            doc => 'picard or samtools for merging',
            is_optional => 1,
        },
        picard_version => {
            doc => 'picard version for MarkDuplicates, MergeSamfiles, CreateSequenceDictionary...',
            is_optional => 1,
        },
        picard_max_sequences_for_disk_read_ends_map => {
            doc => 'picard paremeter for MarkDuplicates',
            is_optional => 1,
        },
        samtools_version => {
            doc => 'samtools version for SamToBam, samtools merge, etc...',
            is_optional => 1,
        },
        rmdup_name => {
            doc => 'rmdup tool used for this model',
            is_optional => 1,
                          },
        rmdup_version => {
            doc => 'rmdup tool version used for this model',
            is_optional => 1,
        },
        read_aligner_name => {
            doc => 'alignment algorithm/software used for this model',
        },
        read_aligner_version => {
            doc => 'the aligner version used for this model',
            is_optional => 1,
        },
        read_aligner_params => {
            doc => 'command line args for the aligner',
            is_optional => 1,
        },
        force_fragment => {
            is => 'Integer',
            #This doesn't seem to work yet because of the create code, can't the valid values logic be removed from create???
            default_value => '0',
            #valid_values => ['0', '1'],
            doc => 'force all alignments as fragment reads',
            is_optional => 1,
        },
        read_trimmer_name => {
            doc => 'trimmer algorithm/software used for this model',
            is_optional => 1,
        },
        read_trimmer_version => {
            doc => 'the trimmer version used for this model',
            is_optional => 1,
        },
        read_trimmer_params => {
            doc => 'command line args for the trimmer',
            is_optional => 1,
        },
        read_calibrator_name => {
            doc => '',
            is_optional => 1,
        },
        read_calibrator_params => {
            doc => '',
            is_optional => 1,
        },
        coverage_stats_params => {
            doc => 'parameters necessary for generating reference coverage in the form of two comma delimited lists split by a colon like 1,5,10,15,20:0,200,500',
            is_optional => 1,
        },
        prior_ref_seq => {
            doc => '',
            is_optional => 1,
        },
        # ehvatum: TODO remove this attribute or make it derive from reference alignment model -> imported reference sequence -> name
        reference_sequence_name => {
            doc => 'identifies the reference sequence used in the model(required if no prior_ref_seq)',
            is_optional => 1,
        },
        capture_set_name => {
            doc => 'The name of the capture set to evaluate coverage and limit variant calls to within the defined target regions',
            is_optional => 1,
            is_deprecated => 1,
        },
        align_dist_threshold => {
            doc => '',
            is_optional => 1,
        },
        annotation_reference_transcripts => {
            doc => 'The reference transcript set used for variant annotation',
            is_optional => 1,
        },
    ],
};

sub _resolve_type_name_for_class {
    return 'reference alignment';
}

# get alignments (generic name)
sub results_for_instrument_data_assignment {
    my ($self, $assignment) = @_;
    #return if $build and $build->id < $assignment->first_build_id;
    return $self->_fetch_alignment_sets($assignment,'get');
}

# create alignments (called by Genome::Model::Event::Build::ReferenceAlignment::AlignReads for now...
sub generate_results_for_instrument_data_assignment {
    my ($self, $assignment) = @_;
    #return if $build and $build->id < $assignment->first_build_id;
    return $self->_fetch_alignment_sets($assignment,'get_or_create');
}

sub _fetch_alignment_sets {
    my $self = shift;
    my $assignment = shift;
    my $mode = shift;

    my $model = $assignment->model;

    my @param_sets = $self->params_for_alignment($assignment);
    unless (@param_sets) {
        $self->error_message('Could not get alignment parameters for this instrument data assignment');
        return;
    }
    my @alignments;    
    for (@param_sets)  {
        my $alignment = Genome::InstrumentData::AlignmentResult->$mode(%$_);
        unless ($alignment) {
             #$self->error_message("Failed to $mode an alignment object");
             return;
         }
        push @alignments, $alignment;
    }
    return @alignments;
}

sub params_for_alignment {
    my $self = shift;
    my $assignment = shift;

    my $model = $assignment->model;
    my $reference_build = $model->reference_build;
    my $reference_build_id = $reference_build->id;

    unless ($self->type_name eq 'reference alignment') {
        $self->error_message('Can not create an alignment object for model type '. $self->type_name);
        return;
    }

    my %params = (
                    instrument_data_id => $assignment->instrument_data_id || undef,
                    aligner_name => $self->read_aligner_name || undef,
                    reference_build_id => $reference_build_id || undef,
                    aligner_version => $self->read_aligner_version || undef,
                    aligner_params => $self->read_aligner_params || undef,
                    force_fragment => $self->force_fragment || undef,
                    trimmer_name => $self->read_trimmer_name || undef,
                    trimmer_version => $self->read_trimmer_version || undef,
                    trimmer_params => $self->read_trimmer_params || undef,
                    picard_version => $self->picard_version || undef,
                    samtools_version => $self->samtools_version || undef,
                    filter_name => $assignment->filter_desc || undef
                );

    #print Data::Dumper::Dumper(\%params);

    my @param_set = (\%params);
    return @param_set;
}


# TODO: remove
sub prior {
    my $self = shift;
    warn("For now prior has been replaced with the actual column name prior_ref_seq");
    if (@_) {
        die("Method prior() is read-only since it's deprecated");
    }
    return $self->prior_ref_seq();
}

# TODO: remove
sub filter_ruleset_name {
    #TODO: move into the db so it's not constant
    'basic'
}

# TODO: remove
sub filter_ruleset_params {
    ''
}


#< SUBCLASSING >#
#
# This is called by the infrastructure to appropriately classify abstract processing profiles
# according to their type name because of the "sub_classification_method_name" setting
# in the class definiton...
sub _X_resolve_subclass_name {
    my $class = shift;

    my $sequencing_platform;
    if ( ref($_[0]) and $_[0]->can('params') ) {
        my @params = $_[0]->params;
        my @seq_plat_param = grep { $_->name eq 'sequencing_platform' } @params;
        if (scalar(@seq_plat_param) == 1) {
            $sequencing_platform = $seq_plat_param[0]->value;
        }

    }  else {
        my %params = @_;
        $sequencing_platform = $params{sequencing_platform};
    }

    unless ( $sequencing_platform ) {
        my $rule = $class->get_rule_for_params(@_);
        $sequencing_platform = $rule->specified_value_for_property_name('sequencing_platform');
    }

    return ( defined $sequencing_platform ) 
    ? $class->_resolve_subclass_name_for_sequencing_platform($sequencing_platform)
    : undef;
}

sub _resolve_subclass_name_for_sequencing_platform {
    my ($class,$sequencing_platform) = @_;
    my @type_parts = split(' ',$sequencing_platform);
	
    my @sub_parts = map { ucfirst } @type_parts;
    my $subclass = join('',@sub_parts);
	
    my $class_name = join('::', 'Genome::ProcessingProfile::ReferenceAlignment' , $subclass);
    return $class_name;
}

sub _resolve_sequencing_platform_for_class {
    my $class = shift;

    my ($subclass) = $class =~ /^Genome::ProcessingProfile::ReferenceAlignment::([\w\d]+)$/;
    return unless $subclass;

    return lc join(" ", ($subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx));
    
    my @words = $subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx;
    return lc(join(" ", @words));
}

#### IMPLEMENTATION #####

sub stages {
    my $self = shift;
$DB::single=1;
    ## second parameter of each pair is the required flag
    ## if it is 1 and no job events are made at start time
    ## a warning will be printed to the user
    my @stages = (
        alignment             => 1,
        deduplication         => 1,
        reference_coverage    => 1,
        variant_detection     => 1,
        transcript_annotation => 0,
        generate_reports      => 0,
    );
    
    my @filtered_stages;
    for (my $i=0; $i < $#stages; $i += 2) {
        my $method = $stages[$i] . '_job_classes';
        
        push @filtered_stages, $stages[$i] if ($stages[$i+1] || $self->$method());
    }
    
    return @filtered_stages;
}

sub alignment_job_classes {
    my @sub_command_classes= qw/
        Genome::Model::Event::Build::ReferenceAlignment::AlignReads
    /;
    return @sub_command_classes;
}

sub reference_coverage_job_classes {
    my $self = shift;
    my $model = shift;
    if ($self->dna_type eq 'cdna' || $self->dna_type eq 'rna') {
        #TODO this needs to be changed to reference build
        my $reference_sequence_build = $model->reference_sequence_build;
        if ($reference_sequence_build->name =~ /^XStrans_adapt_smallRNA_ribo/) {
            my @steps = (
                'Genome::Model::Event::Build::ReferenceAlignment::RefCov',
            );
            return @steps;
        }
    }
    my @steps = (
        'Genome::Model::Event::Build::ReferenceAlignment::CoverageStats',
    );
    return @steps;
}

sub variant_detection_job_classes {
    my $self = shift;
    my @steps = (
        'Genome::Model::Event::Build::ReferenceAlignment::FindVariations'
    );
    if(defined $self->snv_detector_name || defined $self->indel_detector_name) {
        return @steps;
    }
    else {
        return;
    }
}

sub deduplication_job_classes {
    my $self = shift;
    my @steps = ( 
        'Genome::Model::Event::Build::ReferenceAlignment::DeduplicateLibraries',
        'Genome::Model::Event::Build::ReferenceAlignment::PostDedupReallocate',
    );
    if(defined $self->rmdup_name) {
        return @steps;
    }
    else {
        return;
    }
}

sub transcript_annotation_job_classes{
    my $self = shift;
    if (defined($self->annotation_reference_transcripts)){
        my @steps = (
            'Genome::Model::Event::Build::ReferenceAlignment::AnnotateAdaptor',
            #'Genome::Model::Event::Build::ReferenceAlignment::AnnotateTranscriptVariants',
            'Genome::Model::Event::Build::ReferenceAlignment::AnnotateTranscriptVariantsParallel',
        );
        return @steps;
    }
    return;
}

sub generate_reports_job_classes {
    my $self = shift;
    my @steps = (
        'Genome::Model::Event::Build::ReferenceAlignment::RunReports'
    );
    if((defined $self->snv_detector_name || defined $self->indel_detector_name) && defined $self->merge_software && defined $self->rmdup_name) {
        return @steps;
    }
    else {
        return;
    }
}

sub alignment_objects {

    my ($self, $model) = @_;

    my @assignments = $model->instrument_data_assignments();

    $DB::single = 1;

    my @instrument_data_ids = map { $_->instrument_data_id() } @assignments;
    my @solexa_instrument_data = Genome::InstrumentData->get( \@instrument_data_ids );

    unless (scalar @solexa_instrument_data == scalar @instrument_data_ids) {
        my %assignments = map { $_->instrument_data_id => $_ } @assignments;
        for my $found (@solexa_instrument_data) {
            delete $assignments{$found->id};
        }
        my @missing = sort keys %assignments;
        $self->warning_message(
            'Failed to find all of the assigned instrument data for model: '
            . $model->id
            . ".  Missing @missing.  Now trying imported data..."
        );
        my @imported_instrument_data = Genome::InstrumentData::Imported->get( \@instrument_data_ids );
        
        push @solexa_instrument_data, @imported_instrument_data;
        unless (scalar @solexa_instrument_data == scalar @instrument_data_ids) {
            $self->error_message('Still did not find all of the assigned instrument data for model: '.$model->id.' even after trying imported data.  Bailing out!');
            die $self->error_message;
        }
    }
    
    return @solexa_instrument_data;
}

sub reference_coverage_objects {
    my $self = shift;
    my $model = shift;

    my $reference_sequence_build = $model->reference_sequence_build;
    if ($reference_sequence_build->name =~ /^XStrans_adapt_smallRNA_ribo/) {
        return 'all_sequences';
    }
    my @inputs = Genome::Model::Input->get(model_id => $model->id, name => 'region_of_interest_set_name');
    unless (@inputs) { return; }
    return 'all_sequences';
}


sub variant_detection_objects {
    my $self = shift;
    my $model = shift;
    return 'all_sequences';
}

sub deduplication_objects {
    my $self = shift;
    my $model = shift;
    return 'all_sequences';
}

sub generate_reports_objects {
    my $self = shift;
    my $model = shift;
    return 'all_sequences';
}

sub transcript_annotation_objects {
    my $self = shift;
    my $model = shift;
    return 'all_sequences';
}

1;
