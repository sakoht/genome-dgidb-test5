package Genome::Model::Command::AddReads::ProcessLowQualityAlignments::Maq;

use strict;
use warnings;

use above "Genome";
use Command;
use Genome::Model;
use File::Path;
use Data::Dumper;
use Date::Calc;
use File::stat;

class Genome::Model::Command::AddReads::ProcessLowQualityAlignments::Maq {
    is => 'Genome::Model::Event',
};

sub help_brief {
    "Create a new fastq-format file containing reads that aligned poorly in the prior align-reads step";
}

sub help_synopsis {
    return <<"EOS"
    genome-model add-reads process-low-quality-alignments maq --model-id 5 --run-id 10
EOS
}

sub help_detail {                           
    return <<EOS 
This command is usually called as part of the add-reads process
EOS
}

sub should_bsub { 1;}


sub execute {
    my $self = shift;
    
$DB::single = 1;
    my $model = Genome::Model->get(id => $self->model_id);

    my $unique_reads = $self->unaligned_unique_reads_file_for_lane();
    if (-f $unique_reads) {
        return unless $self->_make_fastq_from_unaligned_file($unique_reads, $self->unaligned_unique_fastq_file_for_lane);
    } else {
        $self->error_message("Could not find unique reads file '$unique_reads'");
        return;
    }

    my $dup_reads = $self->unaligned_duplicate_reads_file_for_lane();
    if (-f $dup_reads) {
        return unless $self->_make_fastq_from_unaligned_file($dup_reads, $self->unaligned_duplicate_fastq_file_for_lane);
    } else {
        if (! $model->multi_read_fragment_strategy or
            $model->multi_read_fragment_strategy ne 'EliminateAllDuplicates') {
            $self->error_message("Could not find duplicate reads file '$dup_reads'");
            #We do not fail here because some runs are missing the duplicate data after being faked through CQADR
        }
    }

    unless ($self->verify_successful_completion) {
        $self->error_message("Failed to verify successful completion!");
        return;
    }

    return 1;
}

sub _make_fastq_from_unaligned_file {
    my($self,$in,$fastq) = @_;

    if (-f $fastq && -s $fastq) {
        $self->error_message("fastq file already exists '$fastq'");
        return;
    }

    my $command = Genome::Model::Command::Tools::UnalignedDataToFastq->create(
                           in => $in,
                           fastq => $fastq,
                   );
    unless ($command) {
        $self->error_message("Unable to create the UnalignedDataToFastq command");
        return;
    }

    unless ($command->execute()) {
        $self->error_message("UnalignedDataToFastq command execution failed");
        return;
    }

    return 1;
}

sub verify_successful_completion {
    my $self = shift;
    my $f;

    my $model = Genome::Model->get(id => $self->model_id);
    my $unique_reads = $self->unaligned_unique_reads_file_for_lane();
    if (-f $unique_reads) {
        unless (-f ($f = $self->unaligned_unique_fastq_file_for_lane)) {
            $self->error_message("No unaligned duplicate fastq file $f for " . $self->desc);
        }
    } else {
        $self->error_message("Could not find unique reads file '$unique_reads'");
        return;
    }
 
    my $dup_reads = $self->unaligned_duplicate_reads_file_for_lane();
    if (-f $dup_reads) {
        unless (-f ($f = $self->unaligned_duplicate_fastq_file_for_lane)) {
            $self->error_message("No unaligned duplicate fastq file $f for " . $self->desc);
        }
    } else {
        if (! $model->multi_read_fragment_strategy or
            $model->multi_read_fragment_strategy ne 'EliminateAllDuplicates') {
            $self->error_message("Could not find duplicate reads file '$dup_reads'");
            #We do not fail here because some runs are missing the duplicate data after being faked through CQADR
        }
    }

    return 1;
}

1;

