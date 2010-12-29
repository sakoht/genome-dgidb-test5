package Genome::Model::Tools::Velvet;

use strict;
use warnings;

use POSIX;
use Genome;
use AMOS::AmosLib;
use Data::Dumper;
use Regexp::Common;

class Genome::Model::Tools::Velvet {
    is  => 'Command',
    is_abstract  => 1,
    has_optional => [
        version => {
            is   => 'String',
            doc  => 'velvet version, must be valid velvet version number like 0.7.22, 0.7.30. It takes installed as default.',
            default => 'installed',
        },
    ],
};

sub sub_command_sort_position { 14 }

sub help_brief {
    "Tools to run velvet, a short reads assembler, and work with its output files.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
gmt velvet ...
EOS
}

sub help_detail {
    return <<EOS
EOS
}


sub resolve_version {
    my $self = shift;

    my ($type) = ref($self) =~ /\:\:(\w+)$/;
    $type = 'velvet'.lc(substr $type, 0, 1);

    my $ver = $self->version;
    $ver = 'velvet_'.$ver unless $ver eq 'installed';
    
    my @uname = POSIX::uname();
    $ver .= '-64' if $uname[4] eq 'x86_64';
    
    my $exec = "/gsc/pkg/bio/velvet/$ver/$type";
    unless (-x $exec) {
        $self->error_message("$exec is not excutable");
        return;
    }

    return $exec;
}

sub get_gap_sizes {
    my $self = shift;
    
    my %gap_sizes;

    unless (-e $self->gap_sizes_file) {
        #file should exist 0 size even if assembly has no scaffolds
        #return blank hash if no gap sizes
        $self->error_message("Can't find gap.txt file: ".$self->gap_sizes_file);
        return;
    }

    my $fh = IO::File->new("<".$self->gap_sizes_file) ||
        die "Can not create file handle to read gap.txt file\n";

    while (my $line = $fh->getline) {
        chomp $line;
        my ($contig_name, $gap_size) = split (/\s+/, $line);
        unless ($contig_name =~ /Contig\d+\.\d+/ and $gap_size =~ /\d+/) {
            $self->error_message("Gap.txt file lines should look like this: Contig4.1 125".
                                 "\n\tbut it looks like this: ".$line);
            return;
        }
        $gap_sizes{$contig_name} = $gap_size;
    }
    $fh->close;

    return \%gap_sizes;
}

sub load_read_names_and_seek_pos {
    my ($self, $seq_file) = @_;

    my @seek_positions;
    my $fh = Genome::Utility::FileSystem->open_file_for_reading( $seq_file ) ||
	return;
    my $seek_pos = $fh->tell;
    my $io = Bio::SeqIO->new(-format => 'fasta', -fh => $fh);
    while (my $seq = $io->next_seq) {
	my ($read_index) = $seq->desc =~ /(\d+)\s+\d+$/;
	unless ($read_index) {
            $self->error_message("Failed to get read index number from seq->desc: ".$seq->desc);
            return;
        }
	
	$seek_pos = ( $seek_pos == 0 ) ? $seek_pos : $seek_pos - 1;

        push @{$seek_positions[$read_index]}, $seek_pos;
        push @{$seek_positions[$read_index]}, $seq->primary_id;

        $seek_pos = $fh->tell;
    }
    $fh->close;
    return \@seek_positions;
}

sub get_contig_lengths {
    my ($self, $afg_file) = @_;
    my %contig_lengths;
    my $fh = Genome::Utility::FileSystem->open_file_for_reading($afg_file)
        or return;
    while (my $record = getRecord($fh)) {
        my ($rec, $fields, $recs) = parseRecord($record);
        if ($rec eq 'CTG') {
            my $seq = $fields->{seq};
            $seq =~ s/\n//g;

            my ($sctg_num, $ctg_num) = split('-', $fields->{eid});
            my $contig_name = 'Contig'.--$sctg_num.'.'.++$ctg_num;

            $contig_lengths{$contig_name} = length $seq;
        }
    }
    $fh->close;
    return \%contig_lengths;
}

sub create_edit_dir {
    my $self = shift;

    unless ( -d $self->assembly_directory.'/edit_dir' ) {
	Genome::Utility::FileSystem->create_directory( $self->assembly_directory.'/edit_dir' );
    }

    return 1;
}

#post assemble standard output files
sub contigs_bases_file {
    return $_[0]->assembly_directory.'/edit_dir/contigs.bases';
}

sub contigs_quals_file {
    return $_[0]->assembly_directory.'/edit_dir/contigs.quals';
}

sub gap_sizes_file {
    return $_[0]->assembly_directory.'/edit_dir/gap.txt';
}

sub read_info_file {
    return $_[0]->assembly_directory.'/edit_dir/readinfo.txt';
}

sub reads_placed_file {
    return $_[0]->assembly_directory.'/edit_dir/reads.placed';
}

sub reads_unplaced_file {
    return $_[0]->assembly_directory.'/edit_dir/reads.unplaced';
}

sub reads_unplaced_fasta_file {
    return $_[0]->assembly_directory.'/edit_dir/reads.unplaced.fasta';
}

sub stats_file {
    return $_[0]->assembly_directory.'/edit_dir/stats.txt';
}

sub supercontigs_agp_file {
    return $_[0]->assembly_directory.'/edit_dir/supercontigs.agp';
}

sub supercontigs_fasta_file {
    return $_[0]->assembly_directory.'/edit_dir/supercontigs.fasta';
}

#other files
sub read_names_sqlite {
    return $_[0]->assembly_directory.'/velvet_reads.sqlite';
}

sub input_collated_fastq_file {
    my $self = shift;
    my @files = glob( $self->assembly_directory."/*collated.fastq" );

    unless ( @files == 1 ) {
	$self->error_message("Expected 1 *collated.fastq file but got " . scalar @files);
	return;
    }

    return $files[0];
}

#velvet generated files
sub velvet_afg_file {
    return $_[0]->assembly_directory.'/velvet_asm.afg';
}

sub velvet_contigs_fa_file {
    return $_[0]->assembly_directory.'/contigs.fa';
}

sub velvet_sequences_file {
    return $_[0]->assembly_directory.'/Sequences';
}

1;

