package Genome::Model::Build::GenePrediction::Eukaryotic;

use strict;
use warnings;
use Genome;
use Carp 'confess';

class Genome::Model::Build::GenePrediction::Eukaryotic {
    is => 'Genome::Model::Build::GenePrediction',
};

sub repeat_masker_ace_file {
    my $self = shift;
    return $self->data_directory . "/repeat_masker.ace";
}

sub predictions_ace_file {
    my $self = shift;
    return $self->data_directory . "/predictions.ace";
}

sub log_directory {
    my $self = shift;
    return $self->data_directory . '/logs/';
}

sub resolve_workflow_name {
    my $self = shift;
    return 'eukaryotic gene prediction ' . $self->build_id;
}

sub split_fastas_output_directory {
    my $self = shift;
    return $self->data_directory . '/split_fastas/';
}

sub raw_output_directory {
    my $self = shift;
    return $self->data_directory . '/raw_predictor_output/';
}

sub prediction_directory {
    my $self = shift;
    return $self->data_directory;
}

# Returns a list of sequence names in the assembly contigs file.
# TODO If this is a common request, may want to consider storing the
# sequence names somewhere
sub sequences { 
    my $self = shift;
    my $model = $self->model;
    my $fasta = $model->assembly_contigs_file;
    confess "No fasta file found at $fasta" unless -e $fasta;

    my $seq_obj = Bio::SeqIO->new(
        -file => $fasta,
        -format => 'Fasta',
    );
    confess "Could not create Bio::SeqIO object for $fasta" unless $seq_obj;

    my @sequences;
    while (my $seq = $seq_obj->next_seq) {
        push @sequences, $seq->display_id;
    }

    return \@sequences;
}
    
1;

