package Genome::Model::Event::Build::ReferenceAlignment::AnnotateTranscriptVariantsParallel;

use strict;
use warnings;
use Genome;

class Genome::Model::Event::Build::ReferenceAlignment::AnnotateTranscriptVariantsParallel{
    is => ['Genome::Model::Event'],
    has => [
        analysis_base_path => {
            doc => "the path at which all analysis output is stored",
            calculate_from => ['build'],
            calculate      => q|
            return $build->snp_related_metric_directory;
            |,
            is_constant => 1,
        },
        pre_annotation_filtered_snp_file => {
            doc => "",
            calculate_from => ['analysis_base_path'],
            calculate      => q|
            return $analysis_base_path .'/filtered.indelpe.snps.pre_annotation';
            |,
        },  
        post_annotation_filtered_snp_file => {
            doc => "",
            calculate_from => ['analysis_base_path'],
            calculate      => q|
            return $analysis_base_path .'/filtered.indelpe.snps.post_annotation';
            |,
        }, 
        annotation_log_directory => {
            doc => "The path at which all log output is stored",
            calculate_from => ['build'],
            calculate      => q|
            return $build->log_directory . '/annotation';
            |,
            is_constant => 1,
        },
    ],
};

sub execute {
    my $self = shift;

    unless ($self->check_for_existence($self->pre_annotation_filtered_snp_file)) {
        $self->error_message("Adapted filtered snp file does not exist for annotation");
        return;
    }

    my $annotator = Genome::Model::Tools::Annotate::TranscriptVariantsParallel->create(
        variant_file => $self->pre_annotation_filtered_snp_file,
        output_file => $self->post_annotation_filtered_snp_file,
        reference_transcripts => $self->model->annotation_reference_transcripts,
        annotation_filter => 'top',
        no_headers => 1,
        cache_annotation_data_directory => 1,
        split_by_chromosome => 1,
        log_directory => $self->annotation_log_directory,
    );

    $self->status_message("Executing parallel annotation");
    my $rv = $annotator->execute;
    $self->status_message("Execution complete");
    unless ($rv) {
        $self->error_message("Annotation of adapted filtered snp file failed");
        return;
    }

    return 1;
}

1;
