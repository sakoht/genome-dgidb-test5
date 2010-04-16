package Genome::Model::MetagenomicComposition16s::Report::Summary;

use strict;
use warnings;

use Genome;

use Carp 'confess';
use Data::Dumper 'Dumper';
use Regexp::Common;

class Genome::Model::MetagenomicComposition16s::Report::Summary {
    is => 'Genome::Model::MetagenomicComposition16s::Report',
};

#< Generator >#
sub description {
    return 'Summary Report for '.
    Genome::Utility::Text::capitalize_words( $_[0]->build->description );
}

sub _add_to_report_xml {
    my $self = shift;

    my $build = $self->build;
    unless ( $self->build->amplicons_attempted ) {
        $self->error_message("No amplicons attempted for ".$build->description);
        return;
    }
    
    $self->_create_metrics;

    my @amplicon_sets = $self->build->amplicon_sets
        or return;

    for my $amplicon_set ( @amplicon_sets ) {
        while ( my $amplicon = $amplicon_set->next_amplicon ) {
            $self->_add_amplicon($amplicon);
        }
    }

    # Summary Stats 
    my $summary_stats = $self->get_summary_stats
        or return;
    $self->_add_dataset(
        name => 'stats',
        row_name => 'stat',
        headers => $summary_stats->{headers},
        rows => [ $summary_stats->{stats} ],
    ) or return;

    return 1;
}

sub _create_metrics {
    my $self = shift;

    $self->{_metrix} = {
        lengths => [],
        reads => 0,
        reads_processed => 0,
    };

    return 1;
}

sub _add_amplicon {
    my ($self, $amplicon) = @_;

    # Bioseq
    my $bioseq = $amplicon->oriented_bioseq
        or return 1; # ok - bioseq only returned if assembled and oriented

    # Length
    push @{$self->{_metrix}->{lengths}}, $bioseq->length;

    # Reads
    $self->{_metrix}->{reads} += $amplicon->reads_count;
    $self->{_metrix}->{reads_processed} += $amplicon->reads_processed_count;

    return 1;
}

sub get_summary_stats {
    my $self = shift;

    my $build = $self->build;
    my $attempted = $build->amplicons_attempted;
    my $processed = $build->amplicons_processed;
    my $processed_success = $build->amplicons_processed_success;
    unless ( $processed ) {
        $self->warning_message("No amplicons processed for ".$build->description);
        return {
            headers => [qw/ amplicons-processed amplicons-attempted amplicons-success /],
            stats => [ $processed, $attempted, $processed_success ] 
        };
    }

    my $sum = sub{
        my $total = 0;
        for ( @_ ) { $total += $_; }
        return $total;
    };

    my @lengths = sort { $a <=> $b } @{ $self->{_metrix}->{lengths} };
    my $length = $sum->(@lengths);
    my $reads_processed_success = ( $self->{_metrix}->{reads_processed} > 0 )
    ? sprintf('%.2f', $self->{_metrix}->{reads_processed} / $self->{_metrix}->{reads})
    : 'NA';

    my %totals = (
        # Amplicons
        'amplicons-attempted' => $attempted,
        'amplicons-processed' => $processed,
        'amplicons-processed-success' => $processed_success,
        'amplicons-classified' => $build->amplicons_classified,
        'amplicons-classified-success' => $build->amplicons_classified_success,
        # Lengths
        'length-minimum' => $lengths[0],
        'length-maximum' => $lengths[$#lengths],
        'length-median' => $lengths[( $#lengths / 2 )],
        'length-average' => sprintf(
            '%.0f',
            $length / $processed,
        ),
        # Reads
        reads => $self->{_metrix}->{reads},
        'reads-processed' => $self->{_metrix}->{reads_processed},
        'reads-processed-success' => $reads_processed_success,
    );

    return {
        headers => [ sort { $a cmp $b } keys %totals ],
        stats => [ map { $totals{$_} } sort { $a cmp $b } keys %totals ],
    }
}

1;

#$HeadURL$
#$Id$
