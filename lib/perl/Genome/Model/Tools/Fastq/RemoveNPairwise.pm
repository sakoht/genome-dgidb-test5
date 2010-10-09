package Genome::Model::Tools::Fastq::RemoveNPairwise;

use strict;
use warnings;

use Genome;
use Workflow;
use File::Basename;
use IO::File;
use Bio::SeqIO;

class Genome::Model::Tools::Fastq::RemoveNPairwise
{
    is => 'Genome::Model::Tools',
    has_input => [
            forward_fastq => {
                                    doc => 'file to read forward reads from',
                                    is => 'Text',
                                    is_input => 1,
                                    is_optional => 0,
                                },
            reverse_fastq => {
                                    doc => 'file to read reverse reads from',
                                    is => 'Text',
                                    is_input => 1,
                                    is_optional => 0,
                                },
            fwd_n_removed_file => {
                                    doc => 'file to write to',
                                    is => 'Text',
                                    is_output => 1,
                                    is_optional => 0,
                                },
            rev_n_removed_file => {
                                    doc => 'file to write to',
                                    is => 'Text',
                                    is_output => 1,
                                    is_optional => 0,
                                },
            singleton_n_removed_file => {
                                    doc => 'file to write to',
                                    is => 'Text',
                                    is_output => 1,
                                    is_optional => 0,
                                },
            cutoff =>   {
                                    doc => 'minimum # of N\'s to screen on.  Set to 0 to disable',
                                    is => 'Number',
                                    is_optional => 1,
                                    default => 1, 
                        },
    ],
    has_output => [
            pairs_passed => {is=>'Number',
                             is_optional=>1,
                            },
            singletons_passed => {is=>'Number',
                                 is_optional=>1,
                            },
    ]
};

sub help_brief 
{
    "remove reads from file containing N";
}

sub help_detail
{   
    "Removes reads that have internal N's, or more than cutoff amount of N's on ends.  By default, removes for a single N.  Set cutoff to 0 to disable";
}

sub help_synopsis 
{
    return <<"EOS"
EOS
}

sub create 
{
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    return $self;
}

sub execute 
{
    my $self = shift;
    my $cutoff = $self->cutoff;

    my $fwd_fh = IO::File->new($self->forward_fastq);
    unless ($fwd_fh) {
        $self->error_message("Failed to open fwd input file " . $self->forward_fastq . ": $!");
        return;
    }

    my $rev_fh = IO::File->new($self->reverse_fastq);
    unless ($rev_fh) {
        $self->error_message("Failed to open rev input file " . $self->reverse_fastq . ": $!");
        return;
    }

    my $fwd_output_fh = IO::File->new('>'.$self->fwd_n_removed_file);
    unless ($fwd_output_fh) {
        $self->error_message("Failed to open output file " . $self->fwd_n_removed_file . ": $!");
        return;
    }

    my $rev_output_fh = IO::File->new('>'.$self->rev_n_removed_file);
    unless ($rev_output_fh) {
        $self->error_message("Failed to open output file " . $self->rev_n_removed_file . ": $!");
        return;
    }

    my $sng_output_fh = IO::File->new('>'.$self->singleton_n_removed_file);
    unless ($sng_output_fh) {
        $self->error_message("Failed to open output file " . $self->singleton_n_removed_file . ": $!");
        return;
    }

    my $pairs_passed=0;
    my $singletons_passed=0;

    while (my $fseq = $self->read_seq($fwd_fh)) {
        my $rseq = $self->read_seq($rev_fh);

        if (!$rseq) {
            $self->error_message("Forward sequence file seems longer than reverse.  Are these really paired, or is the reverse truncated?");
            return;
        }

        my $fcount = 0;
        my $rcount = 0;

        $fseq->[1] =~s/(N)/$fcount++;$1/eg; # get N-count
        my $fwdok = ($cutoff > 0 and $fcount < $cutoff);

        $rseq->[1] =~s/(N)/$rcount++;$1/eg; # get N-count
        my $revok = ($cutoff > 0 and $rcount < $cutoff);

        if ($fwdok && $revok) {
            $self->write_seq($fseq, $fwd_output_fh);
            $self->write_seq($rseq, $rev_output_fh);
            $pairs_passed++;
        } elsif ($fwdok) {
            $self->write_seq($fseq, $sng_output_fh);
            $singletons_passed++;
        } elsif ($revok) {
            $self->write_seq($rseq, $sng_output_fh);
            $singletons_passed++;
        }
    }

    if ($self->read_seq($rev_fh)) {
        $self->error_message("Reverse sequence file seems longer than forward.  Are these really paired, or is the forward truncated?");
        return;
    }
    
    $self->pairs_passed($pairs_passed);
    $self->singletons_passed($singletons_passed);

    $self->status_message("Passed $pairs_passed pairs and wrote $singletons_passed singletons out"); return 1;
}

sub read_seq {
    my $self = shift;
    my $fh = shift;

    my $i = 0;
    my @lines;
    my $row;
    while (($i<4) && ($row = $fh->getline)) {
        push @lines, $row; 
        $i++;
    }

    if (@lines == 0) {
        return undef; 
    }

    if (@lines != 4 && $fh->eof) {
        $self->error_message("got eof but didn't read 4 lines. is the file truncated?");
        die $self->error_message;
    }

    return \@lines;
}

sub write_seq {
    my $self = shift;
    my $seq = shift;
    my $fh = shift;
    
    for (@$seq) {
        print $fh $_;
    }

}

1;
