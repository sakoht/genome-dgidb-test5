package Genome::Model::Tools::Sam::SnpFilter;

use strict;
use warnings;

use Genome;
use Command;
use IO::File;

class Genome::Model::Tools::Sam::SnpFilter {
    is  => 'Command',
    has => [
        snp_file => {
            is  => 'String',
            doc => 'The input sam/bam snp file',
        },
    ],
    has_optional => [
        max_map_qual => {
            is  => 'Integer',
            doc => 'max mapping quality of the reads covering the SNP, default 40',
            default => 40,
        },
        min_cns_qual => {
            is  => 'Integer',
            doc => 'minimum consensus quality, default 20',
            default => 20,
        },
        min_read_depth => {
            is  => 'Integer',
            doc => 'minimum read depth to call a SNP, default 3',
            default => 3,
        },
        max_read_depth => {
            is  => 'Integer',
            doc => 'maximum read depth to call a SNP, default 256',
            default => 100000000,
        },
        snp_win_size => {
            is  => 'Integer',
            doc => 'window size for filtering dense SNPs, default 10',
            default => 10,
        },
        max_snp_per_win => {
            is  => 'Integer',
            doc => 'maximum number of SNPs in a sized window',
            default => 2,
        },
        min_snp_qual  => {
            is  => 'Integer',
            doc => 'check minimum snp quality if consensus qual is lower than min_cns_qual, default 20',
            default => 20,
        },
        out_file => {
            is  => 'String',
            doc => 'snp output file after filter',
        },
        indel_file => {
            is  => 'String',
            doc => 'path of sam format indel file to be used as a filter to screen out snps close to indel',
        },
        indel_win_size => {
            is  => 'Integer',
            doc => 'window size of indel position in which SNPs should be filtered out',
            default => 10,
        },
        min_indel_score => {
            is  => 'Integer',
            doc => 'minimum samtools indel score, default is 50',
            default => 50,
        },
    ],
};


sub help_brief {
    'Filter samtools-pileup snp output';
}

sub help_detail {
    return <<EOS
    Filter samtools-pileup snp output. The idea was borrowed from maq.pl SNPfilter.
    Filters are set for read depth, mapping quality, consensus quality, snp dense per
    window
EOS
}



sub execute {
    my $self = shift;
    my $snp_file = $self->snp_file;
    
    unless (-s $snp_file) {
        $self->error_message('Can not find valid SAM snp file: '.$snp_file);
        return;
    }
    
    my %indel_filter;

    if ($self->indel_file) {
        my $indel_fh = Genome::Utility::FileSystem->open_file_for_reading($self->indel_file) or return;

        while (my $indel = $indel_fh->getline) {
            my ($chr, $pos, $id, $indel_seq, $indel_score) = $indel =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+\S+\s+(\S+)\s+/;
            next if $id ne '*' or $indel_seq eq '*/*' or $indel_score < $self->min_indel_score;
            map{$indel_filter{$chr, $_}= 1}($pos - $self->indel_win_size .. $pos + $self->indel_win_size);
        }
        $indel_fh->close;
    }

    my @snps = ();
    my $last_chr = '';
    
    my $out_file = $self->out_file || $self->snp_file . '.sam_SNPfilter';
    my $out_fh = Genome::Utility::FileSystem->open_file_for_writing($out_file) or return;
    my $snp_fh = Genome::Utility::FileSystem->open_file_for_reading($snp_file) or return;
    
    while (my $snp = $snp_fh->getline) {
        my ($chr, $pos, $cns_qual, $snp_qual, $map_qual, $rd_depth) = $snp =~ /^(\S+)\s+(\S+)\s+\S+\s+\S+\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+/;
        next if $indel_filter{$chr,$pos};
        
        my $pass = 1 if $map_qual >= $self->max_map_qual and $rd_depth >= $self->min_read_depth and $rd_depth <= $self->max_read_depth;
        $pass = 0 unless $cns_qual >= $self->min_cns_qual || $snp_qual >= $self->min_snp_qual;
        next unless $pass;
        
        if ($chr ne $last_chr) {
            map{$out_fh->print($_->{line}) if $_->{pass}}@snps;
            @snps = ();       #reset
            $last_chr = $chr; #reset
        }

        push @snps, {
            line => $snp,
            pos  => $pos,
            pass => 1,
        };

        if ($#snps == $self->max_snp_per_win) {
            if ($snps[$#snps]->{pos} - $snps[0]->{pos} < $self->snp_win_size) {
                map{$_->{pass} = 0}@snps;
            }
            $out_fh->print($snps[0]->{line}) if $snps[0]->{pass};
            shift @snps; # keep the size of @snps, moving the window snp by snp, check the snp density in a window for all snps.
        }
    }
    map{$out_fh->print($_->{line}) if $_->{pass}}@snps;

    $snp_fh->close;
    $out_fh->close;
    
    return 1;
}


1;
