package Genome::ProcessingProfile::RnaSeq;

use strict;
use warnings;

use Genome;

class Genome::ProcessingProfile::RnaSeq {
    is => 'Genome::ProcessingProfile::Staged',
    is_abstract => 1,
    subclassify_by => 'subclass_name',
    has => [
        subclass_name => { is_mutable => 0,
                           calculate_from => ['sequencing_platform'],
                           calculate => sub {
                                            my($sequencing_platform) = @_;
                                            Carp::confess "No sequencing platform given to resolve subclass name" unless $sequencing_platform;
                                            return 'Genome::ProcessingProfile::RnaSeq::'.Genome::Utility::Text::string_to_camel_case($sequencing_platform);
                                          }
                         },
    ],

    has_param => [
        sequencing_platform => {
            doc => 'The sequencing platform from whence the model data was generated',
            valid_values => ['454', 'solexa'],
        },
        dna_type => {
            doc => 'the type of dna used in the reads for this model',
            valid_values => ['cdna']
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
        expression_name => {
            doc => 'algorithm used to detect expression levels',
            is_optional => 1,
        },
        expression_version => {
            doc => 'the expression detection version used for this model',
            is_optional => 1,
        },
        expression_params => {
            doc => 'the expression detection params used for this model',
            is_optional => 1,
        },
        picard_version => {
            doc => 'the version of Picard to use when manipulating SAM/BAM files',
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
        annotation_reference_transcripts => {
            doc => 'The reference transcript set used for splice junction annotation',
            is_optional => 1,
        },
        annotation_reference_transcripts_mode => {
            doc => 'The mode to use annotation_reference_transcripts for expression analysis',
            is_optional => 1,
            valid_values => ['de novo','reference guided','reference only',],
        },
    ],
};

sub _resolve_type_name_for_class {
    return 'rna seq';
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
	
    my $class_name = join('::', 'Genome::ProcessingProfile::RnaSeq' , $subclass);
    return $class_name;
}

sub _resolve_sequencing_platform_for_class {
    my $class = shift;

    my ($subclass) = $class =~ /^Genome::ProcessingProfile::RnaSeq::([\w\d]+)$/;
    return unless $subclass;

    return lc join(" ", ($subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx));
    
    my @words = $subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx;
    return lc(join(" ", @words));
}

sub params_for_alignment {
    my $self = shift;
    my @inputs = @_;

    my $model = $inputs[0]->model;
    my $reference_build = $model->reference_sequence_build;
    my $reference_build_id = $reference_build->id;

    my $read_aligner_params = $self->read_aligner_params || undef;
    my $annotation_reference_transcripts = $self->annotation_reference_transcripts;
    if ($annotation_reference_transcripts) {
        my ($annotation_name,$annotation_version) = split(/\//, $annotation_reference_transcripts);
        my $annotation_model = Genome::Model->get(name => $annotation_name);
        unless ($annotation_model){
            $self->error_message('Failed to get annotation model for annotation_reference_transcripts: ' . $annotation_reference_transcripts);
            return;
        }
        unless (defined $annotation_version) {
            $self->error_message('Failed to get annotation version from annotation_reference_transcripts: '. $annotation_reference_transcripts);
            return;
        }
        my $annotation_build = $annotation_model->build_by_version($annotation_version);
        unless ($annotation_build){
            $self->error_message('Failed to get annotation build from annotation_reference_transcripts: '. $annotation_reference_transcripts);
            return;
        }
        my $gtf_path = $annotation_build->annotation_file('gtf',$reference_build_id);
        unless (defined($gtf_path)) {
            die('There is no annotation GTF file defined for annotation_reference_transcripts build: '. $annotation_reference_transcripts);
        }
        if ($read_aligner_params =~ /-G/) {
            die ('This processing_profile is requesting annotation_reference_transcripts \''. $annotation_reference_transcripts .'\', but there seems to be a GTF file already defined in the read_aligner_params: '. $read_aligner_params);
        }
        if (defined($read_aligner_params)) {
            $read_aligner_params .= ' -G '. $gtf_path;
        } else {
            $read_aligner_params = ' -G '. $gtf_path;
        }
    }
    my %params = (
        instrument_data_id => [map($_->value_id, @inputs)],
        aligner_name => 'tophat',
        reference_build_id => $reference_build_id || undef,
        aligner_version => $self->read_aligner_version || undef,
        aligner_params => $read_aligner_params,
        force_fragment => undef, #unused,
        trimmer_name => $self->read_trimmer_name || undef,
        trimmer_version => $self->read_trimmer_version || undef,
        trimmer_params => $self->read_trimmer_params || undef,
        picard_version => $self->picard_version || undef,
        samtools_version => undef, #unused
        filter_name => undef, #unused
        test_name => $ENV{GENOME_SOFTWARE_RESULT_TEST_NAME} || undef,
    );
    #$self->status_message('The AlignmentResult parameters are: '. Data::Dumper::Dumper(%params));
    my @param_set = (\%params);
    return @param_set;
}

1;
