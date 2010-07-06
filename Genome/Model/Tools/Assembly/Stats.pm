package Genome::Model::Tools::Assembly::Stats;

use strict;
use warnings;

use Genome;
use Cwd;
use IO::File;
use AMOS::AmosLib;
use Bio::SeqIO;
use Bio::Seq::Quality;
use Bio::Seq::SequenceTrace;
use Finishing::Assembly::Factory;
use Finishing::Assembly::ContigTools;
use Data::Dumper;

class Genome::Model::Tools::Assembly::Stats {
    is => 'Command',
    has => [],
};

sub help_brief {
    'Tools to run assembly stats'
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools assembly stats
EOS
}

sub help_detail {
    return <<EOS
Tools to run assembly stats .. more later	
EOS
}

sub get_simple_read_stats {
    my ($self) = @_;
    my $stats = "\n*** SIMPLE READ STATS ***\n";

    #INPUT DATA
    my $counts = $self->get_input_counts();

    my $total_input_reads = (exists $counts->{read_count}) ?
	$counts->{read_count} : 0 ;

    my $total_input_bases = (exists $counts->{base_count}) ?
	$counts->{base_count} : 0 ;

    my $total_Q20_bases = (exists $counts->{q20_base_count}) ?
	$counts->{q20_base_count} : 0 ;

    $stats .= "Total input reads: $total_input_reads\n".
	      "Total input bases: $total_input_bases bp\n".
	      "Total Q20 bases: $total_Q20_bases bp\n";

    my $avg_Q20_per_read = int ($total_Q20_bases / $total_input_reads + 0.5);
    my $avg_read_length = int ($total_input_bases / $total_input_reads + 0.5);

    $stats .= "Average Q20 bases per read: $avg_Q20_per_read bp\n".
	      "Average read length: $avg_read_length bp\n";

    #READS PLACED DATA
    my $rp_counts = $self->get_reads_placed_counts();

    my $scaf_reads = (exists $rp_counts->{reads_in_scaffolds}) ?
	$rp_counts->{reads_in_scaffolds} : 0 ;

    my $uniq_scaf_reads = (exists $rp_counts->{uniq_reads_in_scaffolds}) ?
	$rp_counts->{uniq_reads_in_scaffolds} : 0 ;

    my $duplicate_reads = $scaf_reads - $uniq_scaf_reads;
    my $unplaced_reads = $total_input_reads - $uniq_scaf_reads;

    $stats .= "Placed reads: $uniq_scaf_reads\n".
	      "  (reads in scaffolds: $scaf_reads)\n";

    #OPTIONAL UNIQUE READS STATS FOR VELVET AND NEWBLER
    if ($self->assembler eq 'Velvet' or $self->assembler eq 'Newbler') {
	$stats .= "  (unique reads: $uniq_scaf_reads)\n".
	          "  (duplicate reads: $duplicate_reads)\n".
		  "Unplaced reads: $unplaced_reads\n";
    }

    #GENOME CONTENTS STATS FROM CONTIGS.BASES (CB) FILES
    my $cb_counts = $self->get_contigs_bases_counts();

    my $gc_count = ($cb_counts->{gc_count}) ? $cb_counts->{gc_count} : 0 ;
    my $at_count = ($cb_counts->{at_count}) ? $cb_counts->{at_count} : 0 ;
    my $nx_count = ($cb_counts->{nx_count}) ? $cb_counts->{nx_count} : 0 ;

    my $total_contig_length = $cb_counts->{total_contig_bases};

    my $gc_ratio = int (1000 * $gc_count / $total_contig_length + 0.5) / 10;
    my $at_ratio = int (1000 * $gc_count / $total_contig_length + 0.5) / 10;
    my $nx_ratio = int (1000 * $gc_count / $total_contig_length + 0.5) / 10;

    my $genome_contents_stats = "\n*** Genome Contents ***\n".
	                        "Total GC count: $gc_count, (".$gc_ratio."%)\n".
				"Total AT count: $at_count, (".$at_ratio."%)\n".
				"Total NX count: $nx_count, (".$nx_ratio."%)\n".
				"Total: $total_contig_length\n\n";

    #GREATER THAN 5KB CONTIG STATS
    my $ge_5k_contig_length = (exists $cb_counts->{five_kb_contig_length}) ?
	$cb_counts->{five_kb_contig_length} : 0;

    my $ge_5k_ratio = ($ge_5k_contig_length > 0) ?
	int ($ge_5k_contig_length / $total_contig_length * 100) : 0 ;

    my $five_k_stats = "\n*** 5 Kb and Greater Contigs Info ***\n".
	               "Total lengths of all contigs: $total_contig_length\n".
		       "Total lengths of contigs 5 Kb and greater: $ge_5k_contig_length\n".
		       "Percentage of genome: ".$ge_5k_ratio."%\n\n";

    #CHAFF Q20 REDUNDANCY
    my $chaff_rate = int ($unplaced_reads * 10000 / $total_input_reads + 0.5) / 100;
    my $q20_redundancy = int ($total_Q20_bases * 10 / $total_contig_length) / 10; #??

    #CHAFF Q20 REDUNDANCY
    $stats .= "Chaff rate: ".$chaff_rate."%\n".
	      "Q20 base redundancy: ".$q20_redundancy."X\n";

    #TODO - remove prefin stuff ..
    #PREFINISH READS DATA
    my $prefin_input_reads = (exists $counts->{prefin_read_count}) ?
	$counts->{prefin_read_count} : 0 ;

    my $prefin_scaf_reads = (exists $rp_counts->{prefin_reads_in_scaffolds}) ?
	$rp_counts->{prefin_reads_in_scaffolds} : 0 ;

    my $unplaced_prefin_reads = $prefin_input_reads - $prefin_scaf_reads;

    $stats .= "Total prefin reads input: $prefin_input_reads\n".
	      "Total prefin reads unused: $unplaced_prefin_reads\n\n";

    return ($stats, $five_k_stats, $genome_contents_stats);
}

sub get_input_counts {
    my ($self) = @_;
    my $input_quals = $self->get_input_qual_files();
    my $read_counts = $self->parse_input_qual_files($input_quals);
    return $read_counts;
}

sub assembler {
    my ($self) = @_;
    my ($assembler) = ref($self) =~ /(\w+)$/;
    return $assembler;
}

sub get_input_qual_files {
    my ($self) = @_;
    my $all_files = $self->get_edit_dir_file_names();
    #CHECK FOR INPUT FASTA OR CLIP THEN CORRESPONDING FASTA.QUAL OR CLIP.QUAL
    my @input_quals;
    my @input_fastas = grep (/(fasta|clip)\.gz$/, @$all_files);
    foreach my $fasta (@input_fastas) {
	$fasta =~ s/\.gz//;
	my $qual = $fasta.'.qual.gz';
	my @tmp = grep (/$qual/, @$all_files);
	next unless scalar @tmp == 1;
	push @input_quals, $qual;
    }
    return \@input_quals;
}

sub resolve_data_directory {
    my ($self) = @_;
    my $dir = ($self->assembly_directory) ? $self->assembly_directory : cwd();
    #TODO - make assembly_dir main project dir and not edit_dir
    #unless (-d $dir.'/edit_dir') {
        #$self->error_message ("Assembly directory ".$self->assembly_directory." must have an edit_dir");
	#return;
    #}
    unless ($dir =~ /edit_dir$/) {
	$self->error_message ("You must be in edit_dir");
	return;
    }
    chdir "$dir";
    return 1;
}

sub get_edit_dir_file_names {
    my ($self) = @_;
    my @files = glob ("*");
    return \@files;
}

sub parse_input_qual_files {
    my ($self, $files) = @_;
    my $q_cutoff = 20;
#    if ($self->assembler eq 'Velvet') {
#	$q_cutoff += 31;
#    }
    my $counts = {};
    foreach my $file (@$files) {
	my $fh = IO::File->new("zcat $file |")|| return;
	my $qio = Bio::SeqIO->new(-format => 'qual', -fh => $fh);
	while (my $q = $qio->next_seq) {
	    my $read_name = $q->primary_id;
	    $counts->{read_count}++;
	    $counts->{prefin_read_count}++ if $read_name =~ /_t/; #remove this .. no more prefin reads
	    foreach my $qual_value (@{$q->qual}) {
		$counts->{base_count}++;
		$counts->{q20_base_count}++ if $qual_value >= $q_cutoff;
	    }
	}
	$fh->close;
    }
    return $counts;
}

sub get_reads_placed_counts {
    my ($self) = @_;
    my $counts = {};
    my $uniq_reads = {};
    #TODO - create a method to get these files
    my $fh = IO::File->new("< reads.placed") || return;
    while (my $line = $fh->getline) {
	$counts->{reads_in_scaffolds}++;
	my ($read_name) = $line =~ /^\*\s+(\S+)\s+/;
	if ($read_name =~ /_t/) {
	    $counts->{prefin_reads_in_scaffolds}++
	}
	if ($self->assembler eq 'Velvet') {
	    $read_name =~ s/\-\d+$//;
	    $uniq_reads->{$read_name}++;
	}
	elsif ($self->assembler eq 'Newbler') {
	    $read_name =~ s/[\.|\_].*$//;
	    $uniq_reads->{$read_name}++;
	}
	else {
	    next;
	}
    }
    my $uniq_read_count = scalar (keys %$uniq_reads);
    $uniq_reads = '';
    $counts->{uniq_reads_in_scaffolds} = $uniq_read_count;
    $fh->close;
    return $counts;
}

#THIS NEEDED IN CREATE FILES CODES
sub get_fastq_read_base_counts {
    my ($self, $fastq) = @_;
    my $read_count = 0;
    my $base_count = 0;
    my $io = Bio::SeqIO->new(-file => "$fastq", -format => 'fastq');
    while (my $fq = $io->next_seq) {
	$read_count++;
	$base_count += length $fq->seq;
    }
    return $read_count, $base_count;
}
#THIS NEEDED IN CREATE FILES CODES
sub create_input_from_fastq {
    my ($self, $fastq) = @_;
    #THIS NEEDS TO BE MOVED ABOVE BASE CLASS
    unless ($fastq =~ /\.fastq$/) {
	$self->error_message("Fastq file must be named with .fastq extension");
	return
    }
    my ($root_name) = $fastq =~ /(\S+)\.fastq/;

    my $f_fh = IO::File->new(">> $root_name".'.fasta');
    my $f_io = Bio::SeqIO->new(-format => 'fasta', -fh => $f_fh);

    my $q_fh = IO::File->new(">> $root_name".'.fasta.qual');
    my $q_io = Bio::SeqIO->new(-format => 'qual', -fh => $q_fh);

    my $fh = IO::File->new("<$fastq") || return;
    my $fio = Bio::SeqIO->new(-format => 'fastq', -fh => $fh);

    while (my $fq = $fio->next_seq) {
	$f_io->write_seq ($fq);
	#SUBTRACE 31 FROM VELVET QUAL
	my @new_qual = map {$_ - 31} @{$fq->qual};
	$fq->qual(\@new_qual);
	$q_io->write_seq($fq);
    }
    $fh->close;
    $f_fh->close;
    $q_fh->close;
    return 1;
}

sub get_contigs_bases_counts {
    #ACCEPTS CONTIGS.BASES FILE
    #RETURNS TOTAL CONTIG LENGTH, GC AT NX COUNTS, 
    my ($self) = @_;
    my $counts = {};
    #TODO - create a method to get these files
    unless (-s 'contigs.bases') {
	$self->error_message("You must have a contigs.bases file");
	return;
    }
    my $fh = IO::File->new("< contigs.bases") || return;
    my $fio = Bio::SeqIO->new(-format => 'fasta', -fh => $fh);
    while (my $f_seq = $fio->next_seq) {
	my $contig_length = length $f_seq->seq;
	$counts->{total_contig_bases} += $contig_length;
	$counts->{five_kb_contig_length} += $contig_length if $contig_length >= 5000;
	my @tmp = split ('', $f_seq->seq);
	foreach (@tmp) {
	    if ($_ =~ /[gc]/i) {
		$counts->{gc_count}++;
	    }
	    elsif ($_ =~ /[at]/i) {
		$counts->{at_count}++;
	    }
	    elsif ($_ =~ /[nx]/i) {
		$counts->{nx_count}++;
	    }
	    else{
		$self->error_message("None ACGTNX base found in line: $_");
		return;
	    }
	}
    }
    $fh->close;
    return $counts;
}

sub get_contiguity_stats {
    my ($self) = @_;
    my ($counts, $q20_counts) = $self->parse_contigs_quals_file();
    my ($t1, $t2) = $self->_resolve_tier_values();
    my $stats;
    foreach my $type ('contig', 'supercontig') {
	$stats .= $self->create_contiguity_stats ($counts, $q20_counts, $type, $t1, $t2);
    }
    return $stats;
}

sub _resolve_tier_values {
    my ($self) = @_;
    my $t1 = 0;
    my $t2 = 0;
    if ($self->first_tier and $self->second_tier) {
	$t1 = $self->first_tier;
	$t2 = $self->second_tier;
    }
    else {
	my $est_genome_size = -s 'contigs.bases';
	$t1 = int ($est_genome_size * 0.2);
	$t2 = int ($est_genome_size * 0.2);
    }
    return ($t1, $t2);
}

sub _resolve_major_contig_length {
    my ($self) = @_;
    #my $major_contig_length = 100;
    my $major_contig_length = 500;
    if ($self->major_contig_length) {
	$major_contig_length = $self->major_contig_length;
    }
    return $major_contig_length;
}

sub parse_contigs_quals_file {
    my ($self) = @_;
    my ($supercontig_number, $contig_number);
    my $counts = {}; my $q20_counts = {};
    #TODO - create a method to get these files
    unless (-s 'contigs.quals') {
	$self->error_message ("You must have a contigs.quals files");
	return;
    }
    my $fh = IO::File->new("< contigs.quals") || return;
    my $qio = Bio::SeqIO->new(-format => 'qual', -fh => $fh);
    while (my $q = $qio->next_seq) {
	$counts->{total_contig_number}++;
	my $contig_name = $q->primary_id;
	($supercontig_number, $contig_number) = $contig_name =~ /Contig(\d+)\.(\d+)/i;
	$contig_number = $supercontig_number.'.'.$contig_number;
      	foreach my $qual_value (@{$q->qual}) {
	    if ($qual_value >= 20) {
		$q20_counts->{total}->{q20_bases}++;
		$q20_counts->{$contig_number}->{q20_bases}++;
		$q20_counts->{$supercontig_number}->{q20_bases}++;
	    }
	    $counts->{total_contig_length}++;
	    $counts->{contig}->{$contig_number}++;
	    $counts->{supercontig}->{$supercontig_number}++;
	}
    }
    $fh->close;
    return ($counts, $q20_counts);
}

sub create_contiguity_stats {
    my ($self, $counts, $q20_counts, $type, $t1, $t2) = @_;
    #TYPE IS CONTIG OR SUPERCONTIG
    my $major_contig_length = $self->_resolve_major_contig_length();
    my $t3 = $counts->{total_contig_length} - ($t1 + $t2);
    #TOTAL CONTIG VARIABLES
    my $total_contig_number = 0;    my $cumulative_length = 0;
    my $maximum_contig_length = 0;  my $major_contig_number = 0;
    my $major_contig_bases = 0;     my $major_contig_q20_bases = 0;
    my $n50_contig_number = 0;      my $n50_contig_length = 0;
    my $not_reached_n50 = 1;        my $total_q20_bases = 0;
    #TIER 1 VARIABLES
    my $total_t1_bases = 0;         my $total_t1_q20_bases = 0;
    my $t1_n50_contig_number = 0;   my $t1_n50_contig_length = 0;
    my $t1_not_reached_n50 = 1;     my $t1_max_length = 0;
    my $t1_count = 0;
    #TIER 2 VARIABLES
    my $total_t2_bases = 0;         my $total_t2_q20_bases = 0;
    my $t2_n50_contig_number = 0;   my $t2_n50_contig_length = 0;
    my $t2_not_reached_n50 = 1;     my $t2_max_length = 0;
    my $t2_count = 0;
    #TIER 3 VARIABLES
    my $total_t3_bases = 0;         my $total_t3_q20_bases = 0;
    my $t3_n50_contig_number = 0;   my $t3_n50_contig_length = 0;
    my $t3_not_reached_n50 = 1;     my $t3_max_length = 0;
    my $t3_count = 0;
    #ASSESS CONTIG / SUPERCONTIG SIZE VARIABLES
    my $larger_than_1M = 0;         my $larger_than_250K = 0;
    my $larger_than_100K = 0;       my $larger_than_10K = 0;
    my $larger_than_5K = 0;         my $larger_than_2K = 0;
    my $larger_than_0K = 0;

    foreach my $c (sort {$counts->{$type}->{$b} <=> $counts->{$type}->{$a}} keys %{$counts->{$type}}) {
	$total_contig_number++;
	$total_q20_bases += $q20_counts->{$c} if exists $q20_counts->{$c};
	$cumulative_length += $counts->{$type}->{$c};

	if ($counts->{$type}->{$c} >= $major_contig_length) {
	    $major_contig_bases += $counts->{$type}->{$c};
	    $major_contig_q20_bases += $q20_counts->{$c} if exists $q20_counts->{$c};
	    $major_contig_number++;
	}
	if ($not_reached_n50) {
	    $n50_contig_number++;
	    if ($cumulative_length >= $counts->{total_contig_length} * 0.50) {
		$n50_contig_length = $counts->{$type}->{$c};
		$not_reached_n50 = 0;
	    }
	}
	if ($counts->{$type}->{$c} > $maximum_contig_length) {
	    $maximum_contig_length = $counts->{$type}->{$c};
	}
	#TIER 1
	if ($total_t1_bases < $t1) {
	    $total_t1_bases += $counts->{$type}->{$c};
	    $total_t1_q20_bases += $q20_counts->{$c} if exists $q20_counts->{$c};
	    if ($t1_not_reached_n50) {
		$t1_n50_contig_number++;
		if ($cumulative_length >= ($t1 * 0.50)) {
		    $t1_n50_contig_length = $counts->{$type}->{$c};
		    $t1_not_reached_n50 = 0;
		}
	    }
	    $t1_count++;
	    if ($t1_max_length == 0) {
		$t1_max_length = $counts->{$type}->{$c}
	    }
	}
	#TIER 2
	elsif ($total_t2_bases < $t2) {
	    $total_t2_bases += $counts->{$type}->{$c};
	    $total_t2_q20_bases += $q20_counts->{$c} if exists $q20_counts->{$c};
	    if ($t2_not_reached_n50) {
		$t2_n50_contig_number++;
		if ($cumulative_length >= ($t2 * 0.50)) {
		    $t2_n50_contig_length = $counts->{$type}->{$c};
		    $t2_not_reached_n50 = 0;
		}
	    }
	    $t2_count++;
	    if ($t2_max_length == 0) {
		$t2_max_length = $counts->{$type}->{$c}
	    }
	}
	#TIER 3
	else {
	    $total_t3_bases += $counts->{$type}->{$c};
	    $total_t3_q20_bases += $q20_counts->{$c} if exists $q20_counts->{$c};
	    if ($t3_not_reached_n50) {
		$t3_n50_contig_number++;
		if ($cumulative_length >= ($t3 * 0.50)) {
		    $t3_n50_contig_length = $counts->{$type}->{$c};
		    $t3_not_reached_n50 = 0;
		}
	    }
	    $t3_count++;
	    if ($t3_max_length == 0) {
		$t3_max_length = $counts->{$type}->{$c}
	    }
	}

	if ($counts->{$type}->{$c} > 1000000) {
	    $larger_than_1M++;
	}
	elsif ($counts->{$type}->{$c} > 250000) {
	    $larger_than_250K++;
	}
	elsif ($counts->{$type}->{$c} > 100000) {
	    $larger_than_100K++;
	}
	elsif ($counts->{$type}->{$c} > 10000) {
	    $larger_than_10K++;
	}
	elsif ($counts->{$type}->{$c} > 5000) {
	    $larger_than_5K++;
	}
	elsif ($counts->{$type}->{$c} > 2000) {
	    $larger_than_2K++;
	}
	else {
	    $larger_than_0K++;
	}
    }
    #NEED TO ITERATE THROUGH COUNTS HASH AGAGIN FOR N50 SPECIFIC STATS
    my $n50_cumulative_length = 0; my $n50_major_contig_number = 0;
    my $not_reached_major_n50 = 1; my $n50_major_contig_length = 0;
    foreach my $c (sort {$counts->{$type}->{$b} <=> $counts->{$type}->{$a}} keys %{$counts->{$type}}) {
	next unless $counts->{$type}->{$c} > $major_contig_length;
	$n50_cumulative_length += $counts->{$type}->{$c};
	$n50_major_contig_number++ if $not_reached_major_n50;
	if ($not_reached_major_n50) {
	    if ($n50_cumulative_length >= $major_contig_q20_bases * 0.50) {
		$not_reached_major_n50 = 0;
		$n50_major_contig_length = $counts->{$type}->{$c};
	    }
	}
    }

    my $average_contig_length = int ($cumulative_length / $total_contig_number + 0.50);
    my $average_major_contig_length = ($major_contig_number > 0) ?
	int ($major_contig_length / $major_contig_number + 0.50) : 0;
    my $average_t1_contig_length = ($t1_count > 0) ? int ($total_t1_bases/$t1_count + 0.5) : 0;
    my $average_t2_contig_length = ($t2_count > 0) ? int ($total_t2_bases/$t2_count + 0.5) : 0;
    my $average_t3_contig_length = ($t3_count > 0) ? int ($total_t3_bases/$t3_count + 0.5) : 0;

    my $q20_ratio = 0;                  my $t1_q20_ratio = 0;
    my $t2_q20_ratio = 0;               my $t3_q20_ratio = 0;
    my $major_contig_q20_ratio = 0;
    
    if ($self->assembler eq 'Velvet') {
	$total_q20_bases = 'NA';
	$q20_ratio = 'NA';
	$major_contig_q20_bases = 'NA';
	$major_contig_q20_ratio = 'NA';
	$total_t1_q20_bases = 'NA';
	$total_t2_q20_bases = 'NA';
	$total_t3_q20_bases = 'NA';
	$t1_q20_ratio = 'NA';
	$t2_q20_ratio = 'NA';
	$t3_q20_ratio = 'NA';
    }
    else {
	$q20_ratio = int ($total_q20_bases * 1000 / $cumulative_length) / 10;
	$major_contig_q20_ratio = int ($total_q20_bases * 1000 / $major_contig_number) / 10;

	print "T1 $total_t1_bases T2 $total_t2_bases T3 $total_t3_bases\n";

	$t1_q20_ratio = int ($total_t1_q20_bases * 1000 / $total_t1_bases) / 10;
	$t2_q20_ratio = int ($total_t2_q20_bases * 1000 / $total_t2_bases) / 10;
	$t3_q20_ratio = int ($total_t3_q20_bases * 1000 / $total_t3_bases) / 10;
    }

    my $type_name = ucfirst $type;
    my $text = "\n*** Contiguity: $type_name ***\n".
	       "Total $type_name number: $total_contig_number\n".
	       "Total $type_name bases: $cumulative_length bp\n".
	       "Total Q20 bases: $total_q20_bases bp\n".
	       "Q20 bases %: $q20_ratio %\n".
	       "Average $type_name length: $average_contig_length bp\n".
	       "Maximum $type_name length: $maximum_contig_length bp\n".
	       "N50 $type_name length: $n50_contig_length bp\n".
	       "N50 contig number: $n50_contig_number\n".
	       "\n".
	       "Major $type_name (> $major_contig_length bp) number: $major_contig_number\n".
	       "Major $type_name bases: $major_contig_bases bp\n".
	       "Major_$type_name avg contig length: $average_major_contig_length bp\n".
	       "Major_$type_name Q20 bases: $major_contig_q20_bases bp\n".
	       "Major_$type_name Q20 base percent: $major_contig_q20_ratio %\n".
	       "Major_$type_name N50 contig length: $n50_major_contig_length bp\n".
	       "Major_$type_name N50 contig number: $n50_major_contig_number\n".
	       "\n".
	       "Top tier (up to $t1 bp): \n".
	       "  Contig number: $t1_count\n".
	       "  Average length: $average_t1_contig_length bp\n".
	       "  Longest length: $t1_max_length bp\n".
	       "  Contig bases in this tier: $total_t1_bases bp\n".
	       "  Q20 bases in this tier: $total_t1_q20_bases bp\n".
	       "  Q20 base percentage: $t1_q20_ratio %\n".
	       "  Top tier N50 contig length: $t1_n50_contig_length bp\n".
	       "  Top tier N50 contig number: $t1_n50_contig_number\n".
	       "Middle tier ($t1 bp -- ".($t1 + $t2)." bp): \n".
	       "  Contig number: $t2_count\n".
	       "  Average length: $average_t2_contig_length bp\n".
	       "  Longest length: $t2_max_length bp\n".
	       "  Contig bases in this tier: $total_t2_bases bp\n".
	       "  Q20 bases in this tier: $total_t2_q20_bases bp\n".
	       "  Q20 base percentage: $t2_q20_ratio %\n".
	       "  Middle tier N50 contig length: $t2_n50_contig_length bp\n".
	       "  Middle tier N50 contig number: $t2_n50_contig_number\n".
	       "Bottom tier (".($t1 + $t2)." bp -- end): \n".
	       "  Contig number: $t3_count\n".
	       "  Average length: $average_t3_contig_length bp\n".
	       "  Longest length: $t3_max_length bp\n".
	       "  Contig bases in this tier: $total_t3_bases bp\n".
	       "  Q20 bases in this tier: $total_t3_q20_bases bp\n".
	       "  Q20 base percentage: $t3_q20_ratio %\n".
	       "  Bottom tier N50 contig length: $t3_n50_contig_length bp\n".
	       "  Bottom tier N50 contig number: $t3_n50_contig_number\n".
	       "\n";
    if ($type_name eq 'supercontig') {
	$text .= "$type_name > 1M: $larger_than_1M\n".
	         "$type_name 250K--1M: $larger_than_250K\n".
		 "$type_name 100K--250K: $larger_than_100K\n".
		 "$type_name 10--100K: $larger_than_10K\n".
		 "$type_name 5--10K: $larger_than_5K\n".
		 "$type_name 2--5K: $larger_than_2K\n".
		 "$type_name 0--2K: $larger_than_0K\n".
		 "\n";
    }
    return $text;
}

sub get_read_depth_stats_from_afg {
    my $self = shift;

    #TODO - use get method to get this file
    my $velvet_afg_file = $self->assembly_directory.'/../velvet_asm.afg';

    unless (-s $velvet_afg_file) {
	$self->error_message("Can't find velvet_asm.afg file to calculate read depth stats");
	return;
    }

    my $afg_fh = Genome::Utility::FileSystem->open_file_for_reading($velvet_afg_file)
	or return;

    my ($one_x_cov, $two_x_cov, $three_x_cov, $four_x_cov, $five_x_cov, $total_covered_pos) = 0;

    while (my $record = getRecord($afg_fh)) {
	my ($rec, $fields, $recs) = parseRecord($record);
	if ($rec eq 'CTG') {  #contig
	    my $seq = $fields->{seq}; #fasta
	    $seq =~ s/\n//g; #contig seq is written in multiple lines
	    my $contig_length = length $seq;
	    my @consensus_positions;
	    for my $r (0..$#$recs) { #reads
		my ($srec, $sfields, $srecs) = parseRecord($recs->[$r]);
		
		#sfields
		#'src' => '19534',  #read id number
		#'clr' => '0,90',   #read start, stop 0,90 = uncomp 90,0 = comp
		#'off' => '75'      #read off set .. contig start position

		my ($left_pos, $right_pos) = split(',', $sfields->{clr});
		#disregard complementation .. set lower values as left_pos and higher value as right pos
		($left_pos, $right_pos) = $left_pos < $right_pos ? ($left_pos, $right_pos) : ($right_pos, $left_pos);
		#left pos has to be incremented by one since it started at zero
		$left_pos += 1;
		#account for read off set
		$left_pos += $sfields->{off};
		$right_pos += $sfields->{off};
		#limit left and right position to within the boundary of the contig
		$left_pos = 1 if $left_pos < 1;  #read overhangs to left
		$right_pos = $contig_length if $right_pos > $contig_length; #to right
		#
		for ($left_pos .. $right_pos) {
		    $consensus_positions[$_]++;
		}
	    }
	    $total_covered_pos += $#consensus_positions;
	    shift @consensus_positions; #remove [0] position 
	    unless (scalar @consensus_positions == $contig_length) {
		$self->warning_message ("Covered consensus bases does not equal contig length\n\t".
		    "got ".scalar (@consensus_positions)." covered bases but contig length is $contig_length\n");
	    }
	    foreach (@consensus_positions) {
		next unless $_; #could be undef if not covered
		$one_x_cov++ if $_ >= 1;
		$two_x_cov++ if $_ >= 2;
		$three_x_cov++ if $_ >= 3;
		$four_x_cov++ if $_ >= 4;
		$five_x_cov++ if $_ >= 5;
	    }
	}
    }
    $afg_fh->close;

    my $text = "\n*** Read Depth Info ***\n".
	"Total consensus bases: $total_covered_pos\n".
	"Depth >= 5: $five_x_cov\t". $five_x_cov/$total_covered_pos."\n".
	"Depth >= 4: $four_x_cov\t". $four_x_cov/$total_covered_pos."\n".
	"Depth >= 3: $three_x_cov\t". $three_x_cov/$total_covered_pos."\n".
	"Depth >= 2: $two_x_cov\t". $two_x_cov/$total_covered_pos."\n".
	"Depth >= 1: $one_x_cov\t". $one_x_cov/$total_covered_pos."\n\n";

    return $text;
}

sub get_read_depth_stats_from_ace {
    my ($self, $acefile) = @_;

    my $text = "\n*** Read Depth Info ***\n"; #string to store stats text
    if (-s $acefile > 500000000) {
	$text .= "Ace file size exceeds 500Mb and is too large to determine read depth info \n\n";
	return $text;
    }

    my $fo = Finishing::Assembly::Factory->connect('ace', $acefile);
    my $assembly_obj = $fo->get_assembly;
    my $contigs= $assembly_obj->contigs;

    my ($one_x_cov, $two_x_cov, $three_x_cov, $four_x_cov, $five_x_cov, $total_covered_pos) = 0;

    while (my $contig = $contigs->next) {
	my @coverage_depths; #consensus positions covered by reads
	my $reads = $contig->assembled_reads;

	while (my $read = $reads->next) {
	    #error unless read start and stop positions are defined
	    unless (defined $read->start and defined $read->stop) {
		$self->error_message("Reads start and/or stop position not defined\n\t".
				     "start was: ".$read->start." stop was: ".$read->stop);
		return;
	    }
	    #start postion can be < 0 due to low qual areas that don't allign
	    my $start = ($read->start <= 0) ? 1 : $read->start;
	    $start = $contig->pad_position_to_unpad_position($read->start) unless
		$start == 1;
	    #stop position can exceed contig length due to unaligned or low qual regions
	    my $stop = ($read->stop > $contig->unpadded_length) ? $contig->unpadded_length : $read->stop;
	    $stop = $contig->pad_position_to_unpad_position($read->stop) unless
		$stop == $contig->unpadded_length;
	    #increment each read position
	    for ($start .. $stop) {
		$coverage_depths[$_]++;
	    }
	}
	#check to see if # of covered bases == contig length
	shift @coverage_depths; #remove $coverage_depths[0] which is never incremented
	unless (scalar (@coverage_depths) == $contig->unpadded_length) {
	    $self->warning_message("Contig region covered by reads is not the same as contig length for contig: ".$contig->name."\n\t".
				   "covered consensus bases are: ".scalar (@coverage_depths)." contig length is: ".$contig->unpadded_length);
	    #this sometimes happens with velvet assemblies where not all consensus positions are covered by reads .. this is an error
	    #with velvet not assigned proper base segments to reads
	}
	#total up positions of up to 5x coverages
	$total_covered_pos += scalar (@coverage_depths);
	foreach my $depth_num (@coverage_depths) {
	    next unless $depth_num; #can be undef if read base segments are off .. see two comments above
	    $one_x_cov++ if $depth_num >= 1;
	    $two_x_cov++ if $depth_num >= 2;
	    $three_x_cov++ if $depth_num >= 3;
	    $four_x_cov++ if $depth_num >= 4;
	    $five_x_cov++ if $depth_num >= 5;
	}
    }

    $text = "\n*** Read Depth Info ***\n".
	"Total consensus bases: $total_covered_pos\n".
	"Depth >= 5: $five_x_cov\t". $five_x_cov/$total_covered_pos."\n".
	"Depth >= 4: $four_x_cov\t". $four_x_cov/$total_covered_pos."\n".
	"Depth >= 3: $three_x_cov\t". $three_x_cov/$total_covered_pos."\n".
	"Depth >= 2: $two_x_cov\t". $two_x_cov/$total_covered_pos."\n".
	"Depth >= 1: $one_x_cov\t". $one_x_cov/$total_covered_pos."\n\n";
  
    return $text; 
}

sub get_core_gene_survey_results {
    my ($self) = @_;
    my $text = "\n*** Core Gene survey Result ***\n";
    #TODO - use getter method to get this file
    if (-s 'Cov_30_PID_30.out.gz') {
	my $fh = IO::File->new("zcat Cov_30_PID_30.out.gz |");
	while (my $line = $fh->getline) {
	    $text .= $line if $line =~ /^Perc/;
	    $text .= $line if $line =~ /^Number/;
	    $text .= $line if $line =~ /^Core/;
	}
	$text .= "\n";
	$fh->close;
    }
    else {
	$text .= "Cov_30_PID_30.out.gz missing .. unable to create core gene survey results\n\n";
    }
    return $text;
}

sub get_constraint_stats {
    my ($self) = @_;
    my $assembler = $self->assembler;
    my $text = "\n*** Constraints ***\n";
    if ($assembler eq 'pcap') {
	my @files = glob ("*con.pcap.results");
	unless (scalar @files == 1) {
	    $self->error_message("None or multiple possible pcap results file found");
	    return;
	}
	$text .= `tail -12 *.results`."\n";
    }
    else {
	$text .= "Not applicable for $assembler assemblies\n\n";
	
    }
    return $text;
}

#TODO - use methods to get to files
sub contigs_quals_file {
    my $self = shift;
    return $self->assembly_directory.'/edit_dir/contigs.quals';
}

sub contigs_bases_file {
    my $self = shift;
    return $self->assembly_directory.'/edit_dir/contigs.bases';
}

sub reads_placed_file {
    my $self = shift;
    return $self->assembly_directory.'/edit_dir/reads.placed';
}

sub velvet_afg_file {
    my $self = shift;
    return $self->assembly_directory.'/velvet_asm.afg';
}

sub velvet_ace_file {
    my $self = shift;
    return $self->assembly_directory.'/edit_dir/velvet_asm.ace';
}

sub velvet_sequences_file {
    my $self = shift;
    return $self->assembly_directory.'/Sequences';
}

sub core_gene_survey_file {
    my $self = shift;
    return $self->assembly_directory.'/edit_dir/Cov_30_PID_30.out.gz';
}

1;
