package Genome::Model::Tools::Validation::CountContigs;

use strict;
use warnings;

use Genome;
use Genome::Info::IUB;
use IO::File;
use POSIX;

class Genome::Model::Tools::Validation::CountContigs {
    is => 'Command',
    has => [
    contig_fasta_file => {
        type => 'String',
        is_optional => 0,
        doc => 'File of contigs from gmt validation build-remapping-contigs.',
        default => '',
    },
    bam_file => {
        type => 'String',
        is_optional => 0,
        doc => 'File from which to retrieve reads. Must be indexed.',
    },

    ]
};

sub execute {
    my $self=shift;
    $DB::single = 1;
    my $file = $self->contig_fasta_file;

    #TODO Add checks on the files and architecture
    unless (POSIX::uname =~ /64/) {
        $self->error_message("This script requires a 64-bit system to run samtools");
        return;
    }

    unless(-e $self->bam_file && !-z $self->bam_file) {
        $self->error_message($self->bam_file . " does not exist or is of zero size");
        return;
    }

    my $fh = IO::File->new($file, "r");
    unless($fh) {
        $self->error_message("Couldn't open $file: $!"); 
        return;
    }

    #scan through all the fasta headers and grab counts based on each predicted variant and denoted reference
    while(my $line = $fh->getline) {
        next unless $line =~ /^>/;
        chomp $line;
        my @fields = split /\s+/,$line; #this should break down the fields
        $fields[0] =~ s/^>//;   #remove the leading bracket
        my ($pchr, $pstart, $pstop, $ptype, $contig_source) = split("_",$fields[0]);
        my ($has_overlap) = $fields[1] =~ /Overlap:(\d+)/;
        my ($ref_count_chr, $ref_count_start, $ref_count_stop) = $fields[2] =~ /Ref:([^.]+)[.]([0-9]+)[.]([0-9]+)/;
        if($ref_count_start > $ref_count_stop) {
            $self->error_message("Reference coordinates to count make no sense. Swapping start and stop.");
            print STDERR $line,"\n";
            ($ref_count_start,$ref_count_stop) = ($ref_count_stop, $ref_count_start);
        }
        #print STDOUT "$ref_count_chr\t$ref_count_start\t$ref_count_stop\n";

        my $contig_name = $fields[0];
        my ($contig_count_start, $contig_count_stop) = $fields[3] =~ /Con:([0-9]+)[.]([0-9]+)/;

        if($contig_count_start > $contig_count_stop) {
            $self->error_message("Contig coordinates to count make no sense. Swapping start and stop.");
            print STDERR $line, "\n";
            ($contig_count_start,$contig_count_stop) = ($contig_count_stop, $contig_count_start);
        }

        my $ref_count = $self->_count_across_range($self->bam_file,$ref_count_chr, $ref_count_start, $ref_count_stop);
        my $contig_count = $self->_count_across_range($self->bam_file,$contig_name, $contig_count_start, $contig_count_stop);

        print join("\t",$fields[0],$has_overlap,@$ref_count{ qw( total_reads total_reads_above_q1 spanning_reads_q1 ) }, @$contig_count{ qw( total_reads total_reads_above_q1 spanning_reads_q1 ) }), "\n";
    }

    return 1;
}


1;

sub help_brief {
    "Scans a file of contigs, parses information about where they need to be counted and then spits out info."
}

sub help_detail {
    <<'HELP';
HELP
}


#This grabs the reads overlapping the positions
#and checks to see if they contain both potential DNP bases
sub _count_across_range {
    my ($self, $alignment_file, $chr, $pos1, $pos2) = @_;
    unless(open(SAMTOOLS, "samtools view $alignment_file $chr:$pos1-$pos2 |")) {
        $self->error_message("Unable to open pipe to samtools view");
        return;
    }
    my %stats;
    $stats{total_reads_above_q1} = 0;
    $stats{total_reads} = 0;
    $stats{spanning_reads_q1} = 0;

    while( <SAMTOOLS> ) {
        chomp;
        my ($qname, $flag, $rname, $pos_read, $mapq, $cigar, $mrnm, $mpos, $isize, $seq, $qual, $RG, $MF, @rest_of_fields) = split /\t/;

        $stats{'total_reads'}+= 1;
        next if($mapq == 0); #only count q1 and above
        $stats{'total_reads_above_q1'}+= 1;

        my $spans_range = $self->_spans_range($pos1, $pos2, $pos_read, $cigar);

        if($spans_range) {
            $stats{'spanning_reads_q1'}+=1;
        }
    }
    unless(close(SAMTOOLS)) {
        $self->error_message("Error running samtools");
        return;
    }
    else {
        return \%stats;
    }

}

#this calculates the offset of a position into a seqeunce string based on the CIGAR string specifying the alignment
#these are some tests used to test if I got this right.

sub _calculate_offset { 
    my $self = shift;
    my $pos = shift;
    my $read_pos = shift;
    my $cigar = shift;
    my $current_offset=0;
    my $current_pos=$read_pos;
    my @ops = $cigar =~ m/([0-9]+)([MIDNSHP])/g; 
    OP:
    while(my ($cigar_len, $cigar_op) =  splice @ops, 0, 2 ) {
        my $new_offset;
        my $last_pos=$current_pos;
        if($cigar_op eq 'M') {
            $current_pos+=$cigar_len;
            $current_offset+=$cigar_len;
        }
        elsif($cigar_op eq 'I') {
            $current_offset+=$cigar_len;
        }
        elsif($cigar_op eq 'D') {
            $current_pos+=$cigar_len;

        }
        elsif($cigar_op eq 'N') {
            #this is the same as a deletion for returning a base from the read
            $current_pos += $cigar_len;
        }
        elsif($cigar_op eq 'S') {
            #soft clipping means the bases are in the read, but the position (I think) of the read starts at the first unclipped base
            #Functionally this is like an insertion at the beginning of the read
            $current_offset+=$cigar_len;
        }
        elsif($cigar_op eq 'H') {
            #hard clipping means the bases are not in the read and the position of the read starts at the first unclipped base
            #Shouldn't do anything in this case, but ignore it
        }
        else {
            die("CIGAR operation $cigar_op currently unsupported by this module");
        }
        if($pos < $current_pos && $pos >= $last_pos) {
            if($cigar_op eq 'M') {
                my $final_adjustment = $current_pos - $pos;
                return $current_offset - $final_adjustment;
            }
            else {
                return;
            }
        }
    }
    #position didn't cross the read
    return; 
}
    
sub _spans_range { 
    my $self = shift;
    my $pos1 = shift;
    my $pos2 = shift;
    my $read_pos = shift;
    my $cigar = shift;
    my $current_offset=0;
    my $current_pos=$read_pos;
    my @ops = $cigar =~ m/([0-9]+)([MIDNSHP])/g; 
    OP:
    while(my ($cigar_len, $cigar_op) =  splice @ops, 0, 2 ) {
        my $new_offset;
        my $last_pos=$current_pos;
        if($cigar_op eq 'M') {
            $current_pos+=$cigar_len;
            $current_offset+=$cigar_len;
        }
        elsif($cigar_op eq 'I') {
            $current_offset+=$cigar_len;
        }
        elsif($cigar_op eq 'D') {
            $current_pos+=$cigar_len;

        }
        elsif($cigar_op eq 'N') {
            #this is the same as a deletion for returning a base from the read
            $current_pos += $cigar_len;
        }
        elsif($cigar_op eq 'S') {
            #soft clipping means the bases are in the read, but the position (I think) of the read starts at the first unclipped base
            #Functionally this is like an insertion at the beginning of the read
            $current_offset+=$cigar_len;
        }
        elsif($cigar_op eq 'H') {
            #hard clipping means the bases are not in the read and the position of the read starts at the first unclipped base
            #Shouldn't do anything in this case, but ignore it
        }
        else {
            die("CIGAR operation $cigar_op currently unsupported by this module");
        }
        if($pos1 < $current_pos && $pos1 >= $last_pos && $pos2 < $current_pos && $pos2 >= $last_pos) {
            if($cigar_op eq 'M') {
                return 1;
            }
            else {
                return;
            }
        }
    }
    #position didn't cross the read
    return; 
}
