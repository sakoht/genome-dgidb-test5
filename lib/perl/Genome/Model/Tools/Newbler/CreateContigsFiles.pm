package Genome::Model::Tools::Newbler::CreateContigsFiles;

use strict;
use warnings;

use Genome;
use Bio::SeqIO;
use Data::Dumper 'Dumper';

class Genome::Model::Tools::Newbler::CreateContigsFiles {
    is => 'Genome::Model::Tools::Newbler',
    has => [
        assembly_directory => {
            is => 'Text',
            doc => 'Newbler assembly directory',
        },
        min_contig_length => {
            is => 'Number',
            doc => 'Minimum contig length to export',
        },
    ],
};

sub help_brief {
    'Tool to create pcap style contigs.bases and contigs.quals file for newbler assemblies';
}

sub help_detail {
    return <<"EOS"
gmt newbler create-contigs-files --assembly-directory /gscmnt/111/newbler_assembly --min-contig-length 200
EOS
}

sub execute {
    my $self = shift;

    unless ( -d $self->consed_edit_dir ) {
        $self->create_consed_dir;
    }

    unless( $self->_write_unscaffolded_file ) { #TODO - rename this .. works for both scaffolded and unscaffolded
        $self->error_message( "Failed to write unscaffolded fasta and qual files from newbler files" );
        return;
    }

    return 1;
}

sub _write_unscaffolded_file {
    my $self = shift;

    my $scaffolds;
    if ( -s $self->scaffolds_agp_file ) {
        $scaffolds = $self->parse_newbler_scaffold_file;
    }

    #read in
    my $f_i = Bio::SeqIO->new( -format => 'fasta', -file => $self->all_contigs_fasta_file );
    my $q_i = Bio::SeqIO->new( -format => 'qual', -file => $self->all_contigs_qual_file );
    #print out
    my $f_o = Bio::SeqIO->new( -format => 'fasta', -file => '>'.$self->contigs_bases_file );
    my $q_o = Bio::SeqIO->new( -format => 'qual', -file => '>'.$self->contigs_quals_file );

    my $supercontig_number = 0;
    SEQ: while ( my $seq = $f_i->next_seq ) { #fasta
        while ( my $qual = $q_i->next_seq ) { #qual
            #make sure fasta and qual are in same order
            if ( not $seq->primary_id eq $qual->primary_id ) {
                $self->error_message( "Fasta and qual files are out of order: got from fasta, ".$seq->primary_id.", from quality got, ".$qual->primary_id );
                return;
            }

            #new contig name
            my $new_name;
            if ( $scaffolds ) {
                #contigs less than min_length removed while parsing
                next SEQ unless $new_name = $scaffolds->{ $seq->primary_id }->{pcap_name};
            } else {
                #exclude contigs less than min_length
                next SEQ if length $seq->seq < $self->min_contig_length;
                $new_name = 'Contig'.$supercontig_number++.'.1';
            }

            #write fasta
            my %fasta_params = (
                -seq => $seq->seq,
                -id  => $new_name,
            );
            $fasta_params{-desc} = $seq->desc if $seq->desc;
            my $new_seq = Bio::Seq->new( %fasta_params );
            $f_o->write_seq( $new_seq );

            #write qual
            my %qual_params = (
                -seq  => $seq->seq,
                -qual => $qual->qual,
                -id   => $new_name,
            );
            $qual_params{-desc} = $qual->desc if $qual->desc;
            my $new_qual = Bio::Seq::Quality->new( %qual_params );
            $q_o->write_seq( $new_qual );

            next SEQ;
        }
    }

    return 1;
}

1;
