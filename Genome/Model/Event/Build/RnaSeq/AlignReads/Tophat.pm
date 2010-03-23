package Genome::Model::Event::Build::RnaSeq::AlignReads::Tophat;

use strict;
use warnings;

use Genome;

class Genome::Model::Event::Build::RnaSeq::AlignReads::Tophat {
    is => ['Genome::Model::Event::Build::RnaSeq::AlignReads'],
	has => [
    ],
};

sub bsub_rusage {
    return "-R 'select[model!=Opteron250 && type==LINUX64] span[hosts=1] rusage[tmp=50000:mem=8000]' -M 8000000 -n 4";
}


sub execute {
    my $self = shift;
    my $alignment_directory = $self->build->accumulated_alignments_directory;
    unless (-d $alignment_directory) {
        Genome::Utility::FileSystem->create_directory($alignment_directory);
    }
    my $aligner = $self->create_aligner_tool;
    unless ($aligner->execute) {
        $self->error_message('Failed to execute Tophat aligner!');
        return;
    }
    #TODO: remove the fastq files once tophat has completed successfully
    return 1;
}

sub create_aligner_tool {
    my $self = shift;
    my @instrument_data_assignments = $self->build->instrument_data_assignments;
    my @left_reads;
    my @right_reads;
    my $sum_insert_sizes;
    my $sum_insert_size_std_dev;
    my $reads;

    for my $instrument_data_assignment (@instrument_data_assignments) {
        my $instrument_data = $instrument_data_assignment->instrument_data;
        my $prepare_reads = Genome::Model::Event::Build::RnaSeq::PrepareReads->get(
            model_id => $self->model_id,
            build_id => $self->build_id,
            instrument_data_id => $instrument_data->id,
        );
        my $fastq_directory = $prepare_reads->fastq_directory;
        my $left_reads = $fastq_directory.'/'. $instrument_data->read1_fastq_name;
        unless (-s $left_reads) {
            $self->error_message('Failed to find left reads '. $left_reads);
        }
        push @left_reads, $left_reads;
        my $right_reads = $fastq_directory.'/'. $instrument_data->read2_fastq_name;
        unless (-s $right_reads) {
            $self->error_message('Failed to find right reads '. $right_reads);
        }
        push @right_reads, $right_reads;
        my $median_insert_size = $instrument_data->median_insert_size;
        my $sd_above_insert_size = $instrument_data->sd_above_insert_size;
        if ($median_insert_size && $sd_above_insert_size) {
            $sum_insert_sizes += ($median_insert_size * $instrument_data->clusters);
            $sum_insert_size_std_dev += ($sd_above_insert_size * $instrument_data->clusters);
            $reads += $instrument_data->clusters;
        }
    }
    my $insert_size = int( $sum_insert_sizes / $reads );
    my $insert_size_std_dev = int( $sum_insert_size_std_dev / $reads );
    my $reference_build = $self->model->reference_build;
    my $aligner_params = $self->model->read_aligner_params || '';
    my $read_1_fastq_list = join(',',@left_reads);
    my $read_2_fastq_list = join(',',@right_reads);
    my $reference_path = $reference_build->full_consensus_path('bowtie');
    my $transcripts_path = $reference_build->full_consensus_path('gff3');
    if ($transcripts_path) {
        $aligner_params .= ' --GFF '. $transcripts_path;
    }
    unless ($reference_path) {
        $self->error_message('Need to make bowtie reference index in directory: '. $reference_build->data_directory);
        die($self->error_message);
    }
    my %params = (
        reference_path => $reference_path,
        read_1_fastq_list => $read_1_fastq_list,
        read_2_fastq_list => $read_2_fastq_list,
        insert_size => $insert_size,
        insert_std_dev => $insert_size_std_dev,
        aligner_params => $aligner_params,
        alignment_directory => $self->build->accumulated_alignments_directory,
        use_version => $self->model->read_aligner_version,
    );
    my $tool = Genome::Model::Tools::Tophat::AlignReads->create(%params);
    unless ($tool) {
        $self->error_message('Failed to create tophat aligner tool with params:  '. Data::Dumper::Dumper(%params));
        die($self->error_message);
    }
    return $tool;
}

sub verify_successful_completion {
    my $self = shift;
    warn ('Please implement vsc for class '. __PACKAGE__);
    return 1;
}

1;
