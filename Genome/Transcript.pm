package Genome::Transcript;

use strict;
use warnings;

use Genome;

class Genome::Transcript {
    type_name => 'genome transcript',
    table_name => 'TRANSCRIPT',
    id_by => [
        transcript_id => { is => 'NUMBER', len => 10 },
    ],
    has => [
        gene_id => { is => 'NUMBER', len => 10 },
        transcript_start => { is => 'NUMBER', len => 10, is_optional => 1 },
        transcript_stop => { is => 'NUMBER', len => 10, is_optional => 1 },
        transcript_name => { is => 'VARCHAR', len => 255, is_optional => 1 },
        source => { is => 'VARCHAR', len => 7, is_optional => 1 },
        transcript_status => { is => 'VARCHAR', len => 11, is_optional => 1 },
        strand => { is => 'VARCHAR', len => 2, is_optional => 1 },
        chrom_name => { is => 'String', len => 10 },

        sub_structures => { is => 'Genome::TranscriptSubStructure', reverse_id_by => 'transcript', is_many => 1},
        gene => { is => 'Genome::Gene', id_by => 'gene_id' },
        #ordered_sub_structures => { calculate_perl => q( sort { $a->structure_start <=> $b->structure_start } $self->sub_structures ) },
        #cds_exons => { is => 'Genome::TranscriptSubStructure', reverse_id_by => 'transcript', where => [structure_type => 'cds_exon'], is_many => 1 },

        protein => { is => 'Genome::Protein', reverse_id_by => 'transcript', is_many => 1 } , #not really is_many
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::Transcripts',
};


#sub protein {
#    my $self = shift;
#
#    my $protein = Genome::Protein->get(transcript_id => $self->transcript_id);
#    return $protein;
#}


sub structure_at_position {
    my ($self, $position) = @_;

    # check if in range of the trascript
    my @structures = $self->ordered_sub_structures;
    return unless $structures[0]->structure_start <= $position
        and $structures[$#structures]->structure_stop >= $position;

    # get the sub structure
    for my $struct ( @structures ) {
        return $struct if $position >= $struct->structure_start
            and $position <= $struct->structure_stop;
    }

    return;
}

sub structures_flanking_structure_at_position {
    my ($self, $position) = @_;

    # check if in range of the trascript
    my @structures = $self->ordered_sub_structures;
    return unless $structures[0]->structure_start <= $position
        and $structures[$#structures]->structure_stop >= $position;

    my $structure_index = 0;
    for my $struct ( @structures ) {
        last if $position >= $struct->structure_start
            and $position <= $struct->structure_stop;
        $structure_index++;
    }

    return ( $structure_index == 0 ) # don't return [-1], last struct!
    ? (undef, $structures[1])
    : (
        $structures[ $structure_index - 1 ],
        $structures[ $structure_index + 1 ],
    );
}




sub ordered_sub_structures {
    my $self = shift;

    unless (exists $self->{'_ordered_sub_structures'}) {
 
        my @subs = sort { $a->structure_start <=> $b->structure_start } $self->sub_structures;
        $self->{'_ordered_sub_structures'} = \@subs;
    }
    return @{$self->{'_ordered_sub_structures'}};
}


#- CDS EXONS -#

sub cds_exons {
    my $self = shift;

    my @ex = grep { $_->structure_type eq 'cds_exon' } $self->ordered_sub_structures;
    return @ex;
}


sub cds_exon_range {
    my $self = shift;

    my @cds_exons = $self->cds_exons
        or return;

    return ($cds_exons[0]->structure_start, $cds_exons[$#cds_exons]->structure_stop);
}



sub length_of_cds_exons_before_structure_at_position {
    my ($self, $position, $strand) = @_;

    my @cds_exons = $self->cds_exons
        or return;

    my $structure = $self->structure_at_position($position);
    $strand = '+1' unless $strand;

    # Make this an anon sub for slight speed increase
    my $exon_is_before;
    if ( $strand eq '+1' ) {
        my $structure_start = $structure->structure_start;
        $exon_is_before = sub {
            return $_[0]->structure_stop < $structure_start;
        }
    }
    else {
        my $structure_stop = $structure->structure_stop;
        $exon_is_before = sub {
            return $_[0]->structure_start > $structure_stop;
        }
    }

    my $length = 0;
    foreach my $cds_exon ( @cds_exons ) {
        next unless $exon_is_before->($cds_exon);
        $length += $cds_exon->structure_stop - $cds_exon->structure_start + 1;
    }

    return $length;
}


sub cds_exon_with_ordinal {
    my ($self, $ordinal) = @_;

    foreach my $cds_exon ( $self->cds_exons ) {
        return $cds_exon if $cds_exon->ordinal == $ordinal;
    }

    return;
}

sub cds_full_nucleotide_sequence{
    my $self = shift;
    my $seq;
    foreach my $cds_exon ( sort { $a->ordinal <=> $b->ordinal} $self->cds_exons ) {
        $seq.= $cds_exon->nucleotide_seq;
    }
    return $seq;
}


#- GENE -#
sub gene_name
{
    my $self = shift;

    my $gene = $self->gene;
    my $gene_name = $gene->hugo_gene_name;

    return ( $gene_name )
    ? $gene_name
    : ( $self->source eq "genbank" )
    ? $gene->external_ids({ id_type => 'entrez' })->first->id_value
    : $gene->external_ids({ id_type => $self->source })->first->id_value;
}



1;
