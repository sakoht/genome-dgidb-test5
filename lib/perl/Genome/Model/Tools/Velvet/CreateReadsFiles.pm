package Genome::Model::Tools::Velvet::CreateReadsFiles;

use strict;
use warnings;

use Genome;
use IO::File;
use IO::Seekable;
use Bio::SeqIO;
use AMOS::AmosLib;
use Data::Dumper 'Dumper';

class Genome::Model::Tools::Velvet::CreateReadsFiles {
    is => 'Genome::Model::Tools::Velvet',
    has => [
	assembly_directory => {
	    is => 'Text',
	    doc => 'Assembly directory',
	},
        min_contig_length => {
            is => 'Number',
            doc => 'Minimum contig length to export reads for',
        },
        default_gap_size => {
            is => 'Number',
            doc => 'Gap size to assign',
            is_optional => 1,
            default_value => 20,
        }
    ],
};

sub help_brief {
    'Tool to create pcap style readinfo.txt and reads.placed files'
}

sub help_detail {
    return <<EOS
gmt velvet create-reads-files --assembly_directory /gscmnt/111/velvet_assembly --min-contig-length 200
EOS
}

sub execute {
    my $self = shift;

    #make edit_dir
    unless ( $self->create_edit_dir ) {
	$self->error_message("Assembly edit_dir does not exist and could not create one");
	return;
    }

    #readinfo.txt
    unlink $self->read_info_file;
    my $ri_fh = Genome::Sys->open_file_for_writing( $self->read_info_file );

    #reads.placed file
    unlink $self->reads_placed_file;
    my $rp_fh = Genome::Sys->open_file_for_writing( $self->reads_placed_file );

    #velvet output Sequences file
    my $seq_fh = Genome::Sys->open_file_for_reading( $self->velvet_sequences_file );

    #velvet output afg file handle
    my $afg_fh = Genome::Sys->open_file_for_reading( $self->velvet_afg_file );

    #load contigs lengths - gets pcap name contig lengths w/o min length filtering
    my $contig_lengths = $self->get_contig_lengths( $self->velvet_afg_file );
    unless ($contig_lengths) {
	$self->error_message("Failed to get contigs lengths");
	return;
    }

    #stores read names and seek pos in hash or array indexed by read index
    my $seek_positions = $self->load_sequence_seek_positions( $self->velvet_sequences_file );
    unless ($seek_positions) {
	$self->error_message("Failed to load read names and seek pos from Sequences file");
	return;
    }

    my $scaffolds_info;
    #gets velvet named contigs names .. w/o min length filtering
    unless( $scaffolds_info = $self->get_scaffold_info_from_afg_file ) {
        $self->error_message("Failed to get scaffold info from contigs.fa file");
        return;
    }

    my $contig_number = 0;
    while (my $record = getRecord($afg_fh)) {
	my ($rec, $fields, $recs) = parseRecord($record);
	#iterating through contigs
	if ($rec eq 'CTG') {
	    #seq is in multiple lines
	    my $contig_length = $self->_contig_length_from_fields($fields->{seq});
	    unless ($contig_length) {
		$self->error_message("Failed get contig length for seq: ");
		return;
	    }
            #filter contigs less than min length
            my $velvet_contig_name = $fields->{eid};
            $velvet_contig_name =~ s/\-/\./;

            next if $scaffolds_info->{$velvet_contig_name}->{filtered_supercontig_length} < $self->min_contig_length;
            next if $scaffolds_info->{$velvet_contig_name}->{contig_length} < $self->min_contig_length;

	    #convert afg contig format to pcap format
	    my ($sctg_num, $ctg_num) = split('-', $fields->{eid});
            $self->{SUPERCONTIG_NUMBER} = $sctg_num unless exists $self->{SUPERCONTIG_NUMBER};
            if( not $self->{SUPERCONTIG_NUMBER} eq $sctg_num ) {
                $self->{SUPERCONTIG_NUMBER} = $sctg_num;
                $contig_number = 0; #re-set to 0
            }
            my $pcap_supercontig_number = $sctg_num - 1;
            my $contig_name = 'Contig'.$pcap_supercontig_number.'.'.( $ctg_num + 1 );

	    #iterating through reads
	    for my $r (0 .. $#$recs) {
		my ($srec, $sfields, $srecs) = parseRecord($recs->[$r]);
		if ($srec eq 'TLE') {
		    #sfields:
		    #'src' => '19534',  #read id number
		    #'clr' => '0,90',   #read start, stop 0,90 = uncomp 90,0 = comp
		    #'off' => '75'      #read off set .. contig start position

		    # read start, stop pos and orientaion
		    my ($ctg_start, $ctg_stop, $c_or_u) = $self->_read_start_stop_positions($sfields); 

                    #read seek position in velvet Sequences file
                    my $seek_pos = ${$seek_positions}[$sfields->{src}];
                    unless ( defined $seek_pos ) {
                        $self->error_message("Failed to get read name and/or seek position for read id: ".$sfields->{src});
			return;
		    }

                    # read name and length from Sequences file
		    my ($read_length, $read_name) = $self->_read_length_and_name_from_sequences_file( $seek_pos, $seq_fh );

		    # print to readinfo.txt file
		    $ri_fh->print("$read_name $contig_name $c_or_u $ctg_start $read_length\n");

		    # convert C U to 1 0 for reads.placed file
		    $c_or_u = ($c_or_u eq 'U') ? 0 : 1;

		    # calculate contig start pos in supercontig
                    my $sctg_start = $self->_get_supercontig_position( $contig_lengths, $velvet_contig_name );
		    $sctg_start += $ctg_start;

                    # print to reads.placed file
		    $rp_fh->print("* $read_name 1 $read_length $c_or_u $contig_name Supercontig$pcap_supercontig_number $ctg_start $sctg_start\n");
		}
	    }
	}
    }

    $seq_fh->close;
    $afg_fh->close;
    $ri_fh->close;
    $rp_fh->close;

    return 1;
}
sub _contig_length_from_fields {
    my ($self, $seq) = @_;

    #seq is in multiple lines
    $seq =~ s/\n//g;
    
    return length $seq;
}

sub _read_start_stop_positions {
    my ($self, $fields) = @_;

    my ($start, $stop) = split(',', $fields->{clr});
    unless (defined $start and defined $stop) {
	$self->error_message("Failed to get read start, stop positions from record: ".$fields->{clr});
	return;
    }
    #read complementation
    my $c_or_u = ($start > $stop) ? 'C' : 'U';
    #re-direct start, stop to physical contig positions .. regardless of u or c
    ($start, $stop) = $start < $stop ? ($start, $stop) : ($stop, $start);
    $start += $fields->{off} + 1;
    $stop += $fields->{off} + 1;
    
    return $start, $stop, $c_or_u;
}

sub _get_supercontig_position {
    my ($self, $contig_lengths, $contig_name) = @_;

    my ($supercontig_number, $contig_number) = $contig_name =~ /(\d+)\.(\d+)/;
    unless (defined $contig_number and defined $supercontig_number) {
	$self->error_message("Failed to get contig number from contig_name: $contig_name");
	return;
    }
    #0 contig number is first contig in scaffold so start is zero;
    return $contig_number if $contig_number == 0;
    my $supercontig_position;
    #add up contig length and gap sizes 
    while ($contig_number > 0) {
        $contig_number--;
        my $prev_contig_name = $supercontig_number.'.'.$contig_number;
        #total up contig lengths
        unless (exists $contig_lengths->{$prev_contig_name}) {
            $self->error_message("Failed to get contig length for contig: $prev_contig_name");
            return;
        }
        $supercontig_position += $contig_lengths->{$prev_contig_name};
        $supercontig_position += $self->default_gap_size;
    }
    return $supercontig_position;
}

sub _read_length_and_name_from_sequences_file {
    my ($self, $seek_pos, $fh ) = @_;

    $fh->seek( $seek_pos, 0 );
    my $io = Bio::SeqIO->new( -fh => $fh, -format => 'fasta', -noclose => 1 );
    my $seq = $io->next_seq;
    unless ( $seq ) {
        $self->error_message("Failed to get seq object at seek position $seek_pos");
        return;
    }

    return length $seq->seq, $seq->primary_id;
}

1;
