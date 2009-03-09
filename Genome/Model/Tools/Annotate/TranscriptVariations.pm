package Genome::Model::Tools::Annotate::TranscriptVariations;

use strict;
use warnings;

use Genome; 

use Command;
use Data::Dumper;
use IO::File;
use Genome::Utility::IO::SeparatedValueReader;
use Genome::Utility::VariantAnnotator;
use Tie::File;
use Fcntl 'O_RDONLY';
use Carp;

class Genome::Model::Tools::Annotate::TranscriptVariations {
    is => 'Command',
    has => [ 
        snv_file => {
            type => 'Text',
            is_optional => 0,
            doc => "File of single-nucleotide variants.  Tab separated columns: chromosome_name start stop reference variant reference_type type reference_reads variant_reads maq_score",
        },
    ],
    has_optional => [
        output_file => {
            type => 'Text',
            is_optional => 0,
            doc => "Store annotation in the specified file instead of sending it to STDOUT."
        },
        summary_file => {
            type => 'Text',
            is_optional => 1,
            doc => "Store summary metrics about the SNVs analyzed in a file with the specified name."
        },
        no_headers => {
            type => 'Boolean',
            is_optional => 1,
            default => 0,
            doc => 'Exclude headers in report output',
        },
        # Metrix Params
        minimum_maq_score => {
            is => 'Integer',
            is_optional => 1,
            default => 15,
            doc => 'Minimum quality to consider a variant high quality',
        },
        minimum_read_count => {
            is => 'Integer',
            is_optional => 1,
            default => 3,
            doc => 'Minimum number of total reads to consider a variant high quality',
        },
        # Transcript Params
        flank_range => {
            type => 'Integer', 
            is_optional => 1,
            default => 50000,
            doc => 'Range to look around for flaking regions of transcripts',
        },
        # Variation Params
        variation_range => {
           type => 'Integer',
           is_optional => 1,
           default => 0,
           doc => 'Range to look around a variant for known variations',
        },
    ], 
};

############################################################

sub help_synopsis { 
    return <<EOS
gt annotate transcript-variations --snv-file snvs.csv --output-file transcript-changes.csv --summary-file myresults.csv
EOS;
}

sub help_detail {
    return <<EOS 
This launches Xiaoqi's variation annotator.  It takes genome sequence variations and outputs transcript variations, 
with details on the gravity of the change to the transcript.

The current version presumes that the SNVs are human, and that positions are relative to Hs36.  The transcript data 
set is a mix of Ensembl 45 and Genbank transcripts.  Work is in progress to support newer transcript sets, and 
variations from a different reference.
EOS
}

############################################################

sub execute { 
    my $self = shift;
    $DB::single =1;
    
    # generate an iterator for the input list of SNVs
    my $variant_file = $self->snv_file;
    my $variant_svr = Genome::Utility::IO::SeparatedValueReader->create(
        input => $variant_file,
        headers => [qw/
            chromosome_name start stop reference variant 
            reference_type type reference_reads variant_reads
            maq_score
        /],
        separator => '\s+',
        is_regex => 1,
    );
    unless ($variant_svr) {
        $self->error_message("error opening file $variant_file");
        return;
    }
    
    # establish the output handle for the transcript variations
    my $output_fh;
    if (my $output_file = $self->output_file) {
        $output_fh = $self->_create_file($output_file);
    }
    else {
        $output_fh = 'STDOUT';
    }
    $self->_transcript_report_fh($output_fh);
    
    # emit headers as necessary
    $output_fh->print( join(',', $self->transcript_report_headers), "\n" ) unless $self->no_headers;
    
    # annotate all of the input SNVs...
    my $chromosome_name = '';
    my $annotator = undef;
    while ( my $variant = $variant_svr->next ) {
        # make a new annotator when we begin and when we switch chromosomes
        unless ($variant->{chromosome_name} eq $chromosome_name) {
            $chromosome_name = $variant->{chromosome_name};
            $self->status_message("generating annotator for $chromosome_name");
            
            my $transcript_iterator = Genome::Transcript->create_iterator(
                where => [ chrom_name => $chromosome_name]
            );
            die Genome::Transcript->error_message unless $transcript_iterator;
            
            my $transcript_window =  Genome::Utility::Window::Transcript->create (
                iterator => $transcript_iterator, 
                range => $self->flank_range
            );
            die Genome::Utility::Window::Transcript->error_message unless $transcript_window;
            
            $annotator = Genome::Utility::VariantAnnotator->create(
                transcript_window => $transcript_window 
            );
            die Genome::Utility::VariantAnnotator->error_message unless $annotator;
        }
        # get the data and output it
        my @transcripts = $annotator->prioritized_transcripts(%$variant);
        $self->_print_reports_for_snp($variant, \@transcripts);
    }

    # produce a summary as needed
    if (my $summary_file = $self->summary_file) {
        my $summary_fh = $self->_create_file($summary_file);
        $summary_fh->print( join(',', $self->metrics_report_headers), "\n" );
        my $metrics = $self->{_metrics};
        my $result = $summary_fh->print(
            join(
                ',',
                map({ $metrics->{$_} || 0 } $self->metrics_report_headers),
            ),
            "\n",
        );
        unless ($result) {
            die "failed to print a summary report?! : $!";
        }
        $summary_fh->close;
    }
    
    $output_fh->close unless $output_fh eq 'STDOUT';
    return 1;
}

sub _create_file {
    my ($self, $output_file) = @_;
    my $output_fh;
    
    unlink $output_file if -e $output_file;
    if (-e $output_file) {
        $self->warning_message("found previous output file, removing $output_file");
        unlink $output_file;
        if (-e $output_file) {
            die "failed to remove previous file: $! ($output_file)";
        }
    }
    $output_fh = IO::File->new("> $output_file");
    unless ($output_fh) {
        die "Can't open file ($output_file) for writing: $!";
    }
    
    return $output_fh;
}


sub _transcript_report_fh {
    my ($self, $fh) = @_;
    $self->{_transcript_fh} = $fh if $fh;
    return $self->{_transcript_fh};
}

# report headers
sub metrics_report_headers {
    return (qw/ total confident distinct genic /);
}

sub transcript_report_headers {
    return ( variant_attributes(), transcript_attributes());
}

# attributes
sub variant_attributes {
    return (qw/ chromosome_name start stop variant variant_reads reference reference_reads maq_score /);
}

sub transcript_attributes {
    return (qw/ gene_name intensity detection transcript_name strand trv_type c_position amino_acid_change ucsc_cons domain /);
}


#- PRINT REPORTS -#
sub _print_reports_for_snp {
    my ($self, $snp, $transcripts, $variations) = @_;

    # Calculate Metrics
    my $is_hq_snp = ( $snp->{maq_score} >= $self->minimum_maq_score 
            and $snp->{reference_reads} + $snp->{variant_reads} >= $self->minimum_read_count )
    ? 1
    : 0;

    $self->{_metrics}->{total}++;
    $self->{_metrics}->{confident}++ if $is_hq_snp;

    # Basic SNP Info
    my $snp_info_string = join
    (
        ',', 
        map { $snp->{$_} } $self->variant_attributes,
    );

    $self->{_metrics}->{distinct}++ if $is_hq_snp;
    $self->{_metrics}->{genic}++ if @$transcripts;
    
    # Transcripts
    for my $transcripts ( @$transcripts )
    {
        $self->_transcript_report_fh->print
        (
            join
            (
                ',',                   
                $snp_info_string,
                map({ $transcripts->{$_} } $self->transcript_attributes),
            ), 
            "\n",
        );
    }

    return 1;
}

1;

=pod

=head1 Name

Genome::Model::Tools::Annotate::TranscriptVariations

=head1 Synopsis

Goes through each variant in a file, retrieving annotation information from Genome::Utility::VariantAnnotator.

=head1 Usage

 in the shell:
 
     gt annotate transcript-variations --snv-file myinput.csv --output-file myoutput.csv --metric-summary metrics.csv

 in Perl:
 
     $success = Genome::Model::Tools::Annotate::TranscriptVariations->execute(
         snv_file => 'myoutput.csv',
         output_file => 'myoutput.csv',
         summary_file => 'metrics.csv', # optional
         flank_range => 10000, # default 50000
         variation_range => 0, # default 0
     );

=head1 Methods

=over

=item snv_file

An input list of single-nucleotide variations.  The format is:
 chromosome
 position
 reference value
 variant value

=item output_file

The list of transcript changes which would occur as a result of the associated genome sequence changes.

One SNV may result in multiple transcript entries if it intersects multiple transcripts.  One 
transcript may occur multiple times in results if multiple SNVs intersect it.

=item summary_file

A one-row csv "table" with some metrics on the SNVs analyzed.

=item 

=back

=head1 See Also

B<Genome::Utility::VariantAnnotator>, 

=head1 Disclaimer

Copyright (C) 2008 Washington University Genome Sequencing Center

This module is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=head1 Author(s)

Core Logic:
 
 B<Xiaoqi Shi> I<xshi@genome.wustl.edu>

Optimization, Testing, Data Management:
 
 B<Dave Larson> I<dlarson@genome.wustl.edu>
 B<Eddie Belter> I<ebelter@watson.wustl.edu>
 B<Gabriel Sanderson> I<gsanderes@genome.wustl.edu>
 B<Adam Dukes> I<adukes@genome.wustl.edu>
 B<Anthony Brummett> I<abrummet@genome.wustl.edu>

=cut

#$HeadURL$
#$Id$
