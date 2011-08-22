package Genome::Model::Event::Build::RnaSeq::Coverage;

use strict;
use warnings;

use Genome;

class Genome::Model::Event::Build::RnaSeq::Coverage {
    is => ['Genome::Model::Event'],
};

#sub bsub_rusage {
#    return "-R 'select[model!=Opteron250 && type==LINUX64 && mem>=32000] rusage[mem=32000] span[hosts=1]' -M 32000000 -n 4";
#}

sub execute {
    my $self = shift;

    my $alignment_result = $self->build->alignment_result;
    # Tophat v1.1.0 and later produces BAM output
    my $bam_file;
    if (version->parse($alignment_result->aligner_version) >= version->parse('1.1.0')) {
        $bam_file = $alignment_result->bam_file;
    } else {
        die('Coverage requires a BAM file produced by TopHat v1.1.0 or greater');
    }
    # We can use the reference to get GC metrics...
    my $reference_build = $self->model->reference_sequence_build;
    my $reference_path = $reference_build->full_consensus_path('fa');

    my $annotation_reference_transcripts = $self->model->annotation_reference_transcripts;
    my $annotation_build;
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

        $annotation_build = $annotation_model->build_by_version($annotation_version);
        unless ($annotation_build){
            $self->error_message('Failed to get annotation build from annotation_reference_transcripts: '. $annotation_reference_transcripts);
            return;
        }
    } else {
        $self->status_message('Coverage requires annotation_reference_transcripts to be set as a processing profile param. SKIPPING COVERAGE!');
        return 1;
    }
    my $coverage_directory = $self->build->coverage_directory;
    unless (-d $coverage_directory) {
        Genome::Sys->create_directory($coverage_directory);
    }

    my @annotation_file_basenames = qw/annotation rRNA rRNA_protein MT pseudogene/;
    for my $annotation_basename (@annotation_file_basenames) {
        my $annotation_file_method = $annotation_basename .'_file';
        my $bed_file = $annotation_build->$annotation_file_method('bed',$reference_build->id,0);
        unless ($bed_file) {
            die('Failed to find BED annotation transcripts with type: '. $annotation_basename);
        }
        my $stats_file = $coverage_directory .'/'. $annotation_basename .'_exon_STATS.tsv';
        my $transcript_stats_file = $coverage_directory .'/'. $annotation_basename .'_transcript_STATS.tsv';
        my @output_files = ($stats_file,$transcript_stats_file);

        my $cmd = '/usr/bin/perl `which gmt` ref-cov rna-seq --alignment-file-path='. $bam_file .' --roi-file-path='. $bed_file .' --reference-fasta='. $reference_path .' --stats-file='. $stats_file .' --merged-stats-file='. $transcript_stats_file;
        Genome::Sys->shellcmd(
           cmd => $cmd,
            input_files => [$bam_file,$bed_file,$reference_path],
            output_files => \@output_files,
            skip_if_output_is_present => 0,
        );

        my $squashed_bed_file = $annotation_build->$annotation_file_method('bed',$reference_build->id,1);
        unless ($squashed_bed_file) {
            $self->warning_message('Failed to find squashed '. $annotation_file_method .' BED file for reference build '. $reference_build->id .' in: '. $annotation_build->data_directory);
            next;
        }
        my $squashed_stats_file = $coverage_directory .'/'. $annotation_basename .'_squashed_by_gene_STATS.tsv';
        my $genes_stats_file = $coverage_directory .'/'. $annotation_basename .'_gene_STATS.tsv';

        my $gene_cmd = '/usr/bin/perl `which gmt` ref-cov standard --alignment-file-path='. $bam_file .' --roi-file-path='. $squashed_bed_file .' --reference-fasta='. $reference_path .' --stats-file='. $squashed_stats_file .' --alignment-count --merge-by=gene --merged-stats-file='. $genes_stats_file;

        my @squashed_output_files = ($squashed_stats_file, $genes_stats_file);
        Genome::Sys->shellcmd(
            cmd => $gene_cmd,
            input_files => [$bam_file,$squashed_bed_file,$reference_path],
            output_files => \@squashed_output_files,
            skip_if_output_is_present => 0,
        );
        for my $stats_output_file (@squashed_output_files, @output_files) {
            my ($basename,$dirname,$suffix) = File::Basename::fileparse($stats_output_file,qw/\.tsv/);
            my $summary_output_file = $dirname . $basename .'.txt';
            unless (Genome::Model::Tools::BioSamtools::StatsSummary->execute(
                stats_file => $stats_output_file,
                output_file => $summary_output_file,
            )) {
                die('Failed to generate stats sumamry for stats file: '. $stats_output_file);
            }
        }
    }
    # TODO: run once using squashed transcriptome ie. merge entire BED regardless of annotation?
    return 1;
}

1;

