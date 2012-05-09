package Genome::Model::RnaSeq;

use strict;
use warnings;

use Genome;
use version;
use Genome::Utility::Text;

class Genome::Model::RnaSeq {
    is => 'Genome::ModelDeprecated',
    has => [
        subject                      => { is => 'Genome::Sample', id_by => 'subject_id' },
        processing_profile => { is => 'Genome::ProcessingProfile', id_by => 'processing_profile_id', },
        # TODO: Possibly remove accessor
        reference_sequence_build_id  => { via => 'reference_sequence_build', to => 'id' },
        reference_sequence_name      => { via => 'reference_sequence_build', to => 'name' },
    ],
    has_input => [
        reference_sequence_build => {
            is => 'Genome::Model::Build::ImportedReferenceSequence',
        },
        annotation_build => {
            is => "Genome::Model::Build::ImportedAnnotation",
        }
    ],
    has_param => [
        sequencing_platform => {
            doc => 'The sequencing platform from whence the model data was generated',
            valid_values => ['454', 'solexa'],
            is_optional => 1,
        },
        dna_type => {
            doc => 'the type of dna used in the reads for this model',
            valid_values => ['cdna'],
            is_optional => 1,
        },
        read_aligner_name => {
            doc => 'alignment algorithm/software used for this model',
            is_optional => 1,
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
            is_deprecated => 1,
        },
        annotation_reference_transcripts_mode => {
            doc => 'The mode to use annotation_reference_transcripts for expression analysis',
            is_optional => 1,
            valid_values => ['de novo','reference guided','reference only',],
        },
        mask_reference_transcripts => {
            doc => 'The mask level to ignore transcripts located in these annotation features',
            is_optional => 1,
            valid_values => ['rRNA','MT','pseudogene','rRNA_MT','rRNA_MT_pseudogene'],
        },
        fusion_detection_strategy => {
            is_optional => 1,
            is => 'Text',
            doc => 'program, version and params to use for fusion detection ex: chimerascan 0.4.3 [-v]'
        },
        bowtie_version => {
            is_optional => 1,
            is => 'Text',
            doc => 'version of bowtie for tophat to use internally',
        }
    ],
    doc => 'A genome model produced by aligning cDNA reads to a reference sequence.',
};


sub compatible_instrument_data {
    my $self = shift;
    my @compatible_instrument_data = $self->SUPER::compatible_instrument_data(@_);
    return grep{!($_->can('is_paired_end')) or $_->is_paired_end} @compatible_instrument_data;
}

sub _map_workflow_inputs {
    my $self = shift;
    my $build = shift;

    my @inputs = ();

    push @inputs, build_id => $build->id;

    return @inputs;
}

sub _resolve_workflow_for_build {
    # This is called by Genome::Model::Build::start()
    # Returns a Workflow::Operation
    # By default, builds this from stages(), but can be overridden for custom workflow.
    my $self = shift;
    my $build = shift;
    my $lsf_queue = shift; # TODO: the workflow shouldn't need this yet
    my $lsf_project = shift;

    if (!defined $lsf_queue || $lsf_queue eq '' || $lsf_queue eq 'inline') {
        $lsf_queue = 'apipe';
    }
    if (!defined $lsf_project || $lsf_project eq '') {
        $lsf_project = 'build' . $build->id;
    }

    my $output_properties = ['coverage_result','expression_result','metrics_result'];
    push(@$output_properties, 'fusion_result') if $self->fusion_detection_strategy;

    my $workflow = Workflow::Model->create(
        name => $build->workflow_name,
        input_properties => ['build_id',],
        output_properties => $output_properties,
    );

    my $log_directory = $build->log_directory;
    $workflow->log_dir($log_directory);


    my $input_connector = $workflow->get_input_connector;
    my $output_connector = $workflow->get_output_connector;

    # Tophat
    my $tophat_operation = $workflow->add_operation(
        name => 'RnaSeq Tophat Alignment',
        operation_type => Workflow::OperationType::Command->create(
            command_class_name => 'Genome::Model::RnaSeq::Command::AlignReads::Tophat',
        )
    );

    $tophat_operation->operation_type->lsf_queue($lsf_queue);
    $tophat_operation->operation_type->lsf_project($lsf_project);

    my $link = $workflow->add_link(
        left_operation => $input_connector,
        left_property => 'build_id',
        right_operation => $tophat_operation,
        right_property => 'build_id'
    );

    # Picard
    my $picard_operation = $workflow->add_operation(
        name => 'RnaSeq Picard Metrics',
        operation_type => Workflow::OperationType::Command->create(
            command_class_name => 'Genome::Model::RnaSeq::Command::PicardRnaSeqMetrics',
        )
    );
    $picard_operation->operation_type->lsf_queue($lsf_queue);
    $picard_operation->operation_type->lsf_project($lsf_project);

    $workflow->add_link(
        left_operation => $tophat_operation,
        left_property => 'build_id',
        right_operation => $picard_operation,
        right_property => 'build_id'
    );

    # RefCov
    my $coverage_operation = $workflow->add_operation(
        name => 'RnaSeq Coverage',
        operation_type => Workflow::OperationType::Command->create(
            command_class_name => 'Genome::Model::RnaSeq::Command::Coverage',
        )
    );
    $coverage_operation->operation_type->lsf_queue($lsf_queue);
    $coverage_operation->operation_type->lsf_project($lsf_project);

    $workflow->add_link(
        left_operation => $tophat_operation,
        left_property => 'build_id',
        right_operation => $coverage_operation,
        right_property => 'build_id'
    );

    # Cufflinks
    my $cufflinks_operation = $workflow->add_operation(
        name => 'RnaSeq Cufflinks Expression',
        operation_type => Workflow::OperationType::Command->create(
            command_class_name => 'Genome::Model::RnaSeq::Command::Expression::Cufflinks',
        )
    );
    $cufflinks_operation->operation_type->lsf_queue($lsf_queue);
    $cufflinks_operation->operation_type->lsf_project($lsf_project);

    $workflow->add_link(
        left_operation => $tophat_operation,
        left_property => 'build_id',
        right_operation => $cufflinks_operation,
        right_property => 'build_id'
    );

    #Fusion Detection
    if($self->fusion_detection_strategy){
        my ($detector, $version) = split(/\s+/, $self->fusion_detection_strategy);

        my $fusion_detection_operation = $workflow->add_operation(
            name => "RnaSeq Fusion Detection ($detector $version)",
            operation_type => Workflow::OperationType::Command->create(
                command_class_name => 'Genome::Model::RnaSeq::Command::DetectFusions::' . Genome::Utility::Text::string_to_camel_case($detector,"-"),
            )
        );

        $fusion_detection_operation->operation_type->lsf_queue($lsf_queue);
        $fusion_detection_operation->operation_type->lsf_project($lsf_project);

        $workflow->add_link(
            left_operation => $tophat_operation,
            left_property => 'build_id',
            right_operation => $fusion_detection_operation,
            right_property => 'build_id'
        );

        #output connector
        $workflow->add_link(
            left_operation => $fusion_detection_operation,
            left_property => 'result',
            right_operation => $output_connector,
            right_property => 'fusion_result'
        );

    }

    # Define output connector results from coverage and expression
    $workflow->add_link(
        left_operation => $picard_operation,
        left_property => 'result',
        right_operation => $output_connector,
        right_property => 'metrics_result'
    );
    $workflow->add_link(
        left_operation => $coverage_operation,
        left_property => 'result',
        right_operation => $output_connector,
        right_property => 'coverage_result'
    );
    $workflow->add_link(
        left_operation => $cufflinks_operation,
        left_property => 'result',
        right_operation => $output_connector,
        right_property => 'expression_result'
    );

    return $workflow;
}

sub params_for_alignment {
    my $self = shift;
    my @inputs = @_;

    my $reference_build = $self->reference_sequence_build;
    my $reference_build_id = $reference_build->id;

    my $read_aligner_params = $self->read_aligner_params || undef;

    if ($self->annotation_build) {
        my $annotation_build = $self->annotation_build;
        my $gtf_path = $annotation_build->annotation_file('gtf',$reference_build_id);
        unless (defined($gtf_path)) {
            die('There is no annotation GTF file defined for annotation_reference_transcripts build: '. $annotation_build->__display_name__);
        }

        # Test to see if this is version 1.4.0 or greater
        if (version->parse($self->read_aligner_version) >= version->parse('1.4.0')) {
            my $transcriptome_index_prefix = $annotation_build->annotation_file('',$reference_build_id);
            unless (-s $transcriptome_index_prefix .'.fa') {
                # TODO: We should probably lock until the first Tophat job completes creating the transriptome index
            }
            $read_aligner_params .= ' --transcriptome-index '. $transcriptome_index_prefix;
        }

        if ($read_aligner_params =~ /-G/) {
            die ('This processing_profile is requesting annotation_reference_transcripts \''. $annotation_build->__display_name__ .'\', but there seems to be a GTF file already defined in the read_aligner_params: '. $read_aligner_params);
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
        bowtie_version => $self->bowtie_version
    );
    #$self->status_message('The AlignmentResult parameters are: '. Data::Dumper::Dumper(%params));
    my @param_set = (\%params);
    return @param_set;
}

sub publication_description {
    my $self = shift;

    # TODO: use these, to dereive the values in the following two sections
    my $pp = $self->processing_profile;
    my $refseq = $self->reference_sequence_build;
    my $annot = $self->annotation_build;
    my @i = $self->instrument_data;

    # ensure we really only use one lane of data per library like we say we do
    my %libraries;
    for my $i (@i) {
        my $instdata_list = $libraries{$i->library_id} ||= [];
        if ($i->index_sequence) {
            die "the publication description is hard-coded to expect one lane of data per library";
        }
        push @$instdata_list, $i;
    }
    for my $library (keys %libraries) {
        my $i = $libraries{$library};
        if (@$i > 1) {
            die "the publication description is hard-coded to expect one lane of data per library";
        }
    }
    my $lane_count_summary = 'A single lane';

    # TODO: we must look this up from LIMS
    my $instrument = 'CHECKME HiSeq';
    my $chemistry = 'CHECKME v3';
    my $lims_samtools_version = 'CHECKME 0.1.18';
    my $picard_version = 'CHECKME 1.4.6';

    # ensure that we are really on the build 37 reference
    my ($species, $alignment_ref);
    if ($refseq->id == 106942997) {
        $species = 'human';
        $alignment_ref = 'human reference genome (NCBI build 37)';
    }
    else {
        die "the publication description is hard-coded for human build 37 but got " . $refseq->id;
    }

    # ensure everything else we have hard-coded in the description still applies...
    my %expect = (
        read_aligner_name => 'tophat',
        expression_name => 'cufflinks',
    );
    for my $name (sort keys %expect) {
        my $expected_value = $expect{$name};
        my $actual_value = $self->$name;
        unless ($expected_value eq $actual_value) {
            die "publication description is hard-coded to expect that $name is '$expected_value', but got '$actual_value'";
        }
    }

    my $tophat_version = $self->read_aligner_version;
    my $cufflinks_version = $self->expression_version;

    # TODO: update these to come from the model inputs and processing profile
    my $annotation_source = 'CHECKME the human Ensembl database (version 58) (REF)';
    my $bam_index_tool = 'CHECKME samtools (v. 0.1.18)';
    my $bam_sort_tool = 'CHECKME Picard (v.1.46)';

    my $file = __FILE__;
    my $line = __LINE__;

    my $desc = <<EOS;
RNA-seq analysis methods


$lane_count_summary of $instrument ($chemistry chemistry) was generated for each
Illumina RNA-seq library.  Reads were initially aligned to the $species
reference genome using Eland and stored as a BAM file.  These alignments
were used for basic quality assessment purposes only and no read filtering
was performed.  Mapping statistics for the BAM file were generated
using Samtools flagstat (v. $lims_samtools_version) (REF). 
The BAM file was converted to FastQ using Picard (v.$picard_version) (REF)
and all reads were re-aligned to the $alignment_ref
using Tophat (v $tophat_version) (REF).  Tophat was run in default mode with
the following exceptions.  The --mate-inner-dist and --mate-std-dev
were estimated prior to run time using the Eland alignments described
above (elaborate) and specified at run time.  The '-G' option was used
to specify a GTF file for Tophat to generate an exon-exon junction
database to assist in the mapping of known junctions.  The transcripts
for this GTF were obtained from $annotation_source.  The 
resulting tophat BAM file was indexed by $bam_index_tool
and sorted by chromosome mapping position using $bam_sort_tool. 
Transcript expression values were estimated by Cufflinks (v$cufflinks_version)
(REF) using default parameters with the following exceptions.  The Cufflinks 
parameter '-G' was specified to force cufflinks to estimate expression
for known transcripts provided by the same GTF file that was supplied
to TopHat described above.  A second GTF containing only the
mitochondrial and ribosomal sequences was created and Cufflinks was
directed to ignore these regions using the '-M' mask option, to improve
overall robustness of transcript abundance estimates.  The variant
and corresponding gene expression status in the transcriptome were
determined for SNV positions identified as somatic in the WGS
tumor/normal data.  FPKM values were summarized to the gene level by
adding Cufflinks FPKMs from alternative transcripts of each Ensembl gene. 
The variant allele frequencies were determined by counting reads
supporting reference and variant base counts using the Perl module
"Bio::DB::Sam".


Improve this description at line $line of file $file.

EOS

  $desc =~ s/\n(?!\n)/ /g;
  return $desc;
}

1;

