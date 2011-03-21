package Genome::Model::Tools::Bacterial::ExportProteins;

use strict;
use warnings;
use Genome;
use Carp 'confess';

use BAP::DB::SequenceSet;
use BAP::DB::Sequence;
use Bio::Seq;
use Bio::SeqIO;

class Genome::Model::Tools::Bacterial::ExportProteins (
    is => 'Command',
    has => [
        sequence_set_id => { 
            is => 'Number',
            doc => "sequence set id of genes to dump out",
        },
    ],
    has_optional => [
        output_file => {
            is => 'FilePath',
            doc => 'Output is placed in this file',
            default => 'STDOUT',
        },
        phase => {
            is => 'Number',
            doc => "specify which phase of gene merging to dump from",
            default => 5,
        },
        dev => {
            is => 'Boolean',
            doc => "use development database",
            default => 0,
        },
    ],
);

sub help_brief {
    return 'Used to dump proteins for genes from BAP/MGAP database for a certain phase.';
}

sub help_detail {
    return 'This script is for dumping the gene protein sequence from the MGAP database.'
}

sub help_synopsis { help_brief() }

sub execute {
    my $self = shift;

    $BAP::DB::DBI::db_env = 'dev' if $self->dev;
    
    my $output_fh;
    if ($self->output_file eq 'STDOUT') {
        $output_fh = $self->output_file;
    }
    else {
        if (-e $self->output_file) {
            unlink $self->output_file;
            $self->status_message('Removing existing output file at ' . $self->output_file);
        }
        $output_fh = IO::File->new($self->output_file, 'w');
    }

    my $fasta_out = Bio::SeqIO->new(-format => 'Fasta', -fh => $output_fh);

    $self->status_message('Running export proteins on sequence set ' . $self->sequence_set_id . 
        ', sequences being dumped to ' . $self->output_file);

    my $sequence_set = BAP::DB::SequenceSet->retrieve($self->sequence_set_id);
    confess 'Found no sequence set with id ' . $self->sequence_set_id unless $sequence_set;
    my @sequences = $sequence_set->sequences();

    my $phase = 'phase_' . $self->phase;
    for my $sequence (@sequences) {
        my @coding_genes = $sequence->coding_genes($phase => 1);
        foreach my $coding_gene (@coding_genes) {
            my @proteins = $coding_gene->protein();
            foreach my $protein (@proteins) {
                my $seq_string = $protein->sequence_string();
                my $seq_obj = Bio::Seq->new(
                    -seq => $seq_string,
                    -id  => $protein->protein_name(),
                ); 
                $fasta_out->write_seq($seq_obj);
            }
        }
    }

    $output_fh->close;
    return 1;
}

1;
