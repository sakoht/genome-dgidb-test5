use strict;
use warnings;

package Genome::Model::Tools::Somatic::Compare::Bams;

class Genome::Model::Tools::Somatic::Compare::Bams {
    is => ['Workflow::Operation::Command'],
    workflow => sub { Workflow::Operation->create_from_xml(\*DATA); }
};

sub help_synopsis{
    my $self = shift;
    return <<"EOS"
gmt somatic compare bams --normal-bam-file normal.bam --tumor-bam-file tumor.bam --tumor-snp-file tumor.snp --data-directory /some/dir/for/data
EOS
}

sub help_detail {
    my $self = shift;
    return <<"EOS"
gmt somatic compare bams --normal-bam-file normal.bam --tumor-bam-file tumor.bam --tumor-snp-file tumor.snp --data-directory /some/dir/for/data
EOS
}

sub pre_execute {
    my $self = shift;

    # If data directory was provided... make sure it exists and set all of the file names
    if ($self->data_directory) {
        unless (-d $self->data_directory) {
            $self->error_message("Data directory " . $self->data_directory . " does not exist. Please create it.");
            return 0;
        }
        
        for my $param ($self->filenames_to_generate) {
            # set a default param if one has not been specified
            unless ($self->$param) {
                my $default_filename = $self->data_directory . "/$param.out";
                $self->status_message("Param $param was not provided... generated $default_filename as a default");
                $self->$param($default_filename);
            }
        }
    }

    # Set (hardcoded) defaults for tools that have defaults that do not agree with somatic pipeline
    unless ($self->lookup_variants_report_mode) {
        $self->lookup_variants_report_mode("novel-only");
    }
    # Submitters to exclude from somatic pipeline as per dlarson. These guys submit cancer samples to dbsnp, or somesuch
    unless ($self->lookup_variants_filter_out_submitters) {
        $self->lookup_variants_filter_out_submitters("SNP500CANCER,OMIMSNP,CANCER-GENOME,CGAP-GAI,LCEISEN,ICRCG");
    }
    unless ($self->annotate_no_headers) {
        $self->annotate_no_headers(1);
    }
    unless ($self->transcript_annotation_filter) {
        $self->transcript_annotation_filter("top");
    }
    unless ($self->only_tier_1) {
        $self->only_tier_1(0);
    }
    unless ($self->only_tier_1_indel) {
        $self->only_tier_1_indel(1);
    }

    # Verify all of the params that should have been provided or generated
    my $error_count = 0;
    for my $param ($self->filenames_to_generate) {
        unless ($self->$param) {
            $self->error_message("Parameter $param was not provided");
            $error_count++;
        }
    }

    # The output files of indel pe step should go into the workflow directory
    unless ($self->indelpe_data_directory) {
        $self->indelpe_data_directory($self->data_directory);
    }
    # Default ref seq
    unless ($self->indelpe_ref_seq_file) {
        $self->indelpe_ref_seq_file("/gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/all_sequences.fa");
    }

    if ($error_count) {
        # Shouldnt really hit this error... we should only be missing params if the user failed to provide them if they didnt provide data directory
        if ($self->data_directory) {
            $self->error_message("$error_count params were not successfully set by pre-execute using data directory " . $self->data_directory);
        } else {
            $self->error_message("$error_count params were not provided. All params must be specified by hand if no data directory is specified for auto generation");
        }
        exit;
    }

    return 1;
}

sub filenames_to_generate {
    my $self = shift;

    return qw(ucsc_file 
            sniper_snp_output
            sniper_indel_output
            snp_filter_output
            adaptor_output_snp
            dbsnp_output
            annotate_output_snp
            ucsc_output
            ucsc_unannotated_output
            indel_lib_filter_output
            adaptor_output_indel
            annotate_output_indel
            tier_1_snp_file
            tier_2_snp_file
            tier_3_snp_file
            tier_4_snp_file
            tier_1_indel_file
            tier_1_snp_high_confidence_file
            tier_2_snp_high_confidence_file
            tier_3_snp_high_confidence_file
            tier_4_snp_high_confidence_file
            tier_1_indel_high_confidence_file
            ) ;
} 

1;
__DATA__
<?xml version='1.0' standalone='yes'?>

<workflow name="Somatic Pipeline" logDir="/gsc/var/log/genome/somatic_pipeline">

  <link fromOperation="input connector" fromProperty="normal_bam_file" toOperation="Somatic Sniper" toProperty="normal_bam_file" />
  <link fromOperation="input connector" fromProperty="tumor_bam_file" toOperation="Somatic Sniper" toProperty="tumor_bam_file" />
  <link fromOperation="input connector" fromProperty="sniper_snp_output" toOperation="Somatic Sniper" toProperty="output_snp_file" />
  <link fromOperation="input connector" fromProperty="sniper_indel_output" toOperation="Somatic Sniper" toProperty="output_indel_file" />


  <link fromOperation="input connector" fromProperty="tumor_bam_file" toOperation="Indelpe Runner" toProperty="tumor_bam_file" />
  <link fromOperation="input connector" fromProperty="indelpe_ref_seq_file" toOperation="Indelpe Runner" toProperty="ref_seq_file" />
  <link fromOperation="input connector" fromProperty="indelpe_data_directory" toOperation="Indelpe Runner" toProperty="output_dir" />
  <link fromOperation="input connector" fromProperty="tumor_snp_file" toOperation="Indelpe Runner" toProperty="filtered_snp_file" />

  <link fromOperation="Indelpe Runner" fromProperty="filtered_snp_file" toOperation="Snp Filter" toProperty="tumor_snp_file" />
  <link fromOperation="input connector" fromProperty="snp_filter_output" toOperation="Snp Filter" toProperty="output_file" />
  <link fromOperation="Somatic Sniper" fromProperty="output_snp_file" toOperation="Snp Filter" toProperty="sniper_snp_file" />

  <link fromOperation="input connector" fromProperty="adaptor_output_snp" toOperation="Sniper Adaptor Snp" toProperty="output_file" />
  <link fromOperation="Snp Filter" fromProperty="output_file" toOperation="Sniper Adaptor Snp" toProperty="somatic_file" />

  <link fromOperation="input connector" fromProperty="dbsnp_output" toOperation="Lookup Variants" toProperty="output_file" />
  <link fromOperation="Sniper Adaptor Snp" fromProperty="output_file" toOperation="Lookup Variants" toProperty="variant_file" />
  <link fromOperation="input connector" fromProperty="lookup_variants_report_mode" toOperation="Lookup Variants" toProperty="report_mode" />
  <link fromOperation="input connector" fromProperty="lookup_variants_filter_out_submitters" toOperation="Lookup Variants" toProperty="filter_out_submitters" />
  
  <link fromOperation="Lookup Variants" fromProperty="output_file" toOperation="Annotate Transcript Variants Snp" toProperty="variant_file" />
  <link fromOperation="input connector" fromProperty="annotate_output_snp" toOperation="Annotate Transcript Variants Snp" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="annotate_no_headers" toOperation="Annotate Transcript Variants Snp" toProperty="no_headers" />
  <link fromOperation="input connector" fromProperty="transcript_annotation_filter" toOperation="Annotate Transcript Variants Snp" toProperty="annotation_filter" />

  <link fromOperation="Lookup Variants" fromProperty="output_file" toOperation="Annotate UCSC" toProperty="input_file" />
  <link fromOperation="input connector" fromProperty="ucsc_output" toOperation="Annotate UCSC" toProperty="output_file" /> 
  <link fromOperation="input connector" fromProperty="ucsc_unannotated_output" toOperation="Annotate UCSC" toProperty="unannotated_file" /> 
  <link fromOperation="input connector" fromProperty="only_tier_1" toOperation="Annotate UCSC" toProperty="skip" /> 
    
  <link fromOperation="input connector" fromProperty="tier_1_snp_file" toOperation="Tier Variants Snp" toProperty="tier1_file" />
  <link fromOperation="input connector" fromProperty="tier_2_snp_file" toOperation="Tier Variants Snp" toProperty="tier2_file" />
  <link fromOperation="input connector" fromProperty="tier_3_snp_file" toOperation="Tier Variants Snp" toProperty="tier3_file" />
  <link fromOperation="input connector" fromProperty="tier_4_snp_file" toOperation="Tier Variants Snp" toProperty="tier4_file" />
  <link fromOperation="input connector" fromProperty="only_tier_1" toOperation="Tier Variants Snp" toProperty="only_tier_1" />
  <link fromOperation="Annotate UCSC" fromProperty="output_file" toOperation="Tier Variants Snp" toProperty="ucsc_file" />
  <link fromOperation="Somatic Sniper" fromProperty="output_snp_file" toOperation="Tier Variants Snp" toProperty="variant_file" />
  <link fromOperation="Annotate Transcript Variants Snp" fromProperty="output_file" toOperation="Tier Variants Snp" toProperty="transcript_annotation_file" />

  <link fromOperation="input connector" fromProperty="tumor_bam_file" toOperation="High Confidence Snp Tier 1" toProperty="tumor_bam_file" />
  <link fromOperation="input connector" fromProperty="tier_1_snp_high_confidence_file" toOperation="High Confidence Snp Tier 1" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="tumor_bam_file" toOperation="High Confidence Snp Tier 2" toProperty="tumor_bam_file" />
  <link fromOperation="input connector" fromProperty="tier_2_snp_high_confidence_file" toOperation="High Confidence Snp Tier 2" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="tumor_bam_file" toOperation="High Confidence Snp Tier 3" toProperty="tumor_bam_file" />
  <link fromOperation="input connector" fromProperty="tier_3_snp_high_confidence_file" toOperation="High Confidence Snp Tier 3" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="tumor_bam_file" toOperation="High Confidence Snp Tier 4" toProperty="tumor_bam_file" />
  <link fromOperation="input connector" fromProperty="tier_4_snp_high_confidence_file" toOperation="High Confidence Snp Tier 4" toProperty="output_file" />
  <link fromOperation="Tier Variants Snp" fromProperty="tier1_file" toOperation="High Confidence Snp Tier 1" toProperty="sniper_file" />
  <link fromOperation="Tier Variants Snp" fromProperty="tier2_file" toOperation="High Confidence Snp Tier 2" toProperty="sniper_file" />
  <link fromOperation="Tier Variants Snp" fromProperty="tier3_file" toOperation="High Confidence Snp Tier 3" toProperty="sniper_file" />
  <link fromOperation="Tier Variants Snp" fromProperty="tier4_file" toOperation="High Confidence Snp Tier 4" toProperty="sniper_file" />
  <link fromOperation="input connector" fromProperty="only_tier_1" toOperation="High Confidence Snp Tier 2" toProperty="skip" /> 
  <link fromOperation="input connector" fromProperty="only_tier_1" toOperation="High Confidence Snp Tier 3" toProperty="skip" /> 
  <link fromOperation="input connector" fromProperty="only_tier_1" toOperation="High Confidence Snp Tier 4" toProperty="skip" /> 

  <link fromOperation="High Confidence Snp Tier 1" fromProperty="output_file" toOperation="output connector" toProperty="tier_1_snp_high_confidence" />
  <link fromOperation="High Confidence Snp Tier 2" fromProperty="output_file" toOperation="output connector" toProperty="tier_2_snp_high_confidence" />
  <link fromOperation="High Confidence Snp Tier 3" fromProperty="output_file" toOperation="output connector" toProperty="tier_3_snp_high_confidence" />
  <link fromOperation="High Confidence Snp Tier 4" fromProperty="output_file" toOperation="output connector" toProperty="tier_4_snp_high_confidence" />

  <link fromOperation="input connector" fromProperty="indel_lib_filter_output" toOperation="Library Support Filter" toProperty="output_file" />
  <link fromOperation="Somatic Sniper" fromProperty="output_indel_file" toOperation="Library Support Filter" toProperty="indel_file" />

  <link fromOperation="input connector" fromProperty="adaptor_output_indel" toOperation="Sniper Adaptor Indel" toProperty="output_file" />
  <link fromOperation="Library Support Filter" fromProperty="output_file" toOperation="Sniper Adaptor Indel" toProperty="somatic_file" />

  <link fromOperation="Sniper Adaptor Indel" fromProperty="output_file" toOperation="Annotate Transcript Variants Indel" toProperty="variant_file" />
  <link fromOperation="input connector" fromProperty="annotate_output_indel" toOperation="Annotate Transcript Variants Indel" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="annotate_no_headers" toOperation="Annotate Transcript Variants Indel" toProperty="no_headers" />
  <link fromOperation="input connector" fromProperty="transcript_annotation_filter" toOperation="Annotate Transcript Variants Indel" toProperty="annotation_filter" />

  <link fromOperation="input connector" fromProperty="tier_1_indel_file" toOperation="Tier Variants Indel" toProperty="tier1_file" />
  <link fromOperation="input connector" fromProperty="only_tier_1_indel" toOperation="Tier Variants Indel" toProperty="only_tier_1" />
  <link fromOperation="Library Support Filter" fromProperty="output_file" toOperation="Tier Variants Indel" toProperty="variant_file" />
  <link fromOperation="Annotate Transcript Variants Indel" fromProperty="output_file" toOperation="Tier Variants Indel" toProperty="transcript_annotation_file" />

  <link fromOperation="Tier Variants Indel" fromProperty="tier1_file" toOperation="High Confidence Indel Tier 1" toProperty="sniper_file" />
  <link fromOperation="input connector" fromProperty="tumor_bam_file" toOperation="High Confidence Indel Tier 1" toProperty="tumor_bam_file" />
  <link fromOperation="input connector" fromProperty="tier_1_indel_high_confidence_file" toOperation="High Confidence Indel Tier 1" toProperty="output_file" />

  <link fromOperation="High Confidence Indel Tier 1" fromProperty="output_file" toOperation="output connector" toProperty="tier_1_indel_high_confidence" />

  <operation name="Somatic Sniper">
    <operationtype commandClass="Genome::Model::Tools::Somatic::Sniper" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operation name="Indelpe Runner">
    <operationtype commandClass="Genome::Model::Tools::Somatic::IndelpeRunner" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operation name="Snp Filter">
    <operationtype commandClass="Genome::Model::Tools::Somatic::SnpFilter" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Sniper Adaptor Snp">
    <operationtype commandClass="Genome::Model::Tools::Annotate::Adaptor::Sniper" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Lookup Variants">
      <operationtype commandClass="Genome::Model::Tools::Annotate::LookupVariants" typeClass="Workflow::OperationType::Command" />
  </operation>   
  <operation name="Annotate UCSC">
      <operationtype commandClass="Genome::Model::Tools::Somatic::UcscAnnotator" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Annotate Transcript Variants Snp">
    <operationtype commandClass="Genome::Model::Tools::Annotate::TranscriptVariants" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Tier Variants Snp">
    <operationtype commandClass="Genome::Model::Tools::Somatic::TierVariants" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="High Confidence Snp Tier 1">
    <operationtype commandClass="Genome::Model::Tools::Somatic::HighConfidence" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="High Confidence Snp Tier 2">
    <operationtype commandClass="Genome::Model::Tools::Somatic::HighConfidence" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="High Confidence Snp Tier 3">
    <operationtype commandClass="Genome::Model::Tools::Somatic::HighConfidence" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="High Confidence Snp Tier 4">
    <operationtype commandClass="Genome::Model::Tools::Somatic::HighConfidence" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operation name="Library Support Filter">
    <operationtype commandClass="Genome::Model::Tools::Somatic::LibrarySupportFilter" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Sniper Adaptor Indel">
    <operationtype commandClass="Genome::Model::Tools::Annotate::Adaptor::Sniper" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Annotate Transcript Variants Indel">
    <operationtype commandClass="Genome::Model::Tools::Annotate::TranscriptVariants" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Tier Variants Indel">
    <operationtype commandClass="Genome::Model::Tools::Somatic::TierVariants" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="High Confidence Indel Tier 1">
    <operationtype commandClass="Genome::Model::Tools::Somatic::HighConfidence" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operationtype typeClass="Workflow::OperationType::Model">
    <inputproperty>normal_bam_file</inputproperty>
    <inputproperty>tumor_bam_file</inputproperty>
    <inputproperty isOptional="Y">tumor_snp_file</inputproperty>

    <inputproperty isOptional="Y">only_tier_1</inputproperty>
    <inputproperty isOptional="Y">only_tier_1_indel</inputproperty>

    <inputproperty isOptional="Y">data_directory</inputproperty>
    <inputproperty isOptional="Y">ucsc_file</inputproperty>
    <inputproperty isOptional="Y">sniper_snp_output</inputproperty>
    <inputproperty isOptional="Y">sniper_indel_output</inputproperty>

    <inputproperty isOptional="Y">indelpe_data_directory</inputproperty>
    <inputproperty isOptional="Y">indelpe_ref_seq_file</inputproperty>

    <inputproperty isOptional="Y">snp_filter_output</inputproperty>

    <inputproperty isOptional="Y">adaptor_output_snp</inputproperty>

    <inputproperty isOptional="Y">dbsnp_output</inputproperty>
    <inputproperty isOptional="Y">lookup_variants_report_mode</inputproperty>
    <inputproperty isOptional="Y">lookup_variants_filter_out_submitters</inputproperty>

    <inputproperty isOptional="Y">annotate_output_snp</inputproperty>
    <inputproperty isOptional="Y">annotate_no_headers</inputproperty>
    <inputproperty isOptional="Y">transcript_annotation_filter</inputproperty>
    
    <inputproperty isOptional="Y">ucsc_output</inputproperty>
    <inputproperty isOptional="Y">ucsc_unannotated_output</inputproperty>

    <inputproperty isOptional="Y">tier_1_snp_file</inputproperty>
    <inputproperty isOptional="Y">tier_2_snp_file</inputproperty>
    <inputproperty isOptional="Y">tier_3_snp_file</inputproperty>
    <inputproperty isOptional="Y">tier_4_snp_file</inputproperty>

    <inputproperty isOptional="Y">tier_1_snp_high_confidence_file</inputproperty>
    <inputproperty isOptional="Y">tier_2_snp_high_confidence_file</inputproperty>
    <inputproperty isOptional="Y">tier_3_snp_high_confidence_file</inputproperty>
    <inputproperty isOptional="Y">tier_4_snp_high_confidence_file</inputproperty>
    
    <inputproperty isOptional="Y">tier_1_indel_file</inputproperty>
    <inputproperty isOptional="Y">tier_1_indel_high_confidence_file</inputproperty>

    <outputproperty>tier_1_snp_high_confidence</outputproperty>
    <outputproperty>tier_2_snp_high_confidence</outputproperty>
    <outputproperty>tier_3_snp_high_confidence</outputproperty>
    <outputproperty>tier_4_snp_high_confidence</outputproperty>

    <inputproperty isOptional="Y">indel_lib_filter_output</inputproperty>
    <inputproperty isOptional="Y">adaptor_output_indel</inputproperty>
    <inputproperty isOptional="Y">annotate_output_indel</inputproperty>

    <outputproperty>tier_1_indel_high_confidence</outputproperty>
  </operationtype>

</workflow>


