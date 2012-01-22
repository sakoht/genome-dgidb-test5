package Genome::Model::Tools::Velvet::Metrics;

use strict;
use warnings;

use Genome;

use AMOS::AmosLib;

class Genome::Model::Tools::Velvet::Metrics {
    is => 'Genome::Model::Tools::Velvet::Base',
    has => [
	    first_tier => {
            type => 'Integer',
            is_optional => 1,
            doc => "first tier value",
        },
        second_tier => {
            type => 'Integer',
            is_optional => 1,
            doc => "second tier value",
        },
        assembly_directory => {
            type => 'Text',
            is_optional => 1,
            doc => "path to assembly",
        },
        major_contig_length => {
            type => 'Integer',
            is_optional => 1,
            default_value => 500,
            doc => "Major contig length cutoff",
        },
        output_file => {
            is => 'Text',
            is_optional => 1,
            doc => 'Stats output file',
        },
    ],
    has_optional => [
        _metrics => { is_transient => 1, },
    ],
};

sub help_brief {
    return 'Produce metrics for velvet assemblies'
}

sub __errors__ {
    my $self = shift;

    my @errors = $self->SUPER::__errors__(@_);
    return @errors if @errors;

    if ( $self->assembly_directory ) {
        if ( not -d $self->assembly_directory ) {
            push @errors, UR::Object::Tag->create(
                type => 'invalid',
                properties => [qw/ assembly_directory /],
                desc => 'The assembly_directory is not a directory!',
            );
            return @errors;
        }
        if ( not defined $self->output_file ) {
            my $create_edit_dir = $self->create_edit_dir;
            return if not $create_edit_dir;
            $self->output_file( $self->stats_file );
        }
    }
    elsif ( not $self->output_file ) { 
        push @errors, UR::Object::Tag->create(
            type => 'invalid',
            properties => [qw/ output_file /],
            desc => 'No output file given and no assembly_directory given to determine the output file!',
        );
    }

    my $reads_file = $self->input_collated_fastq_file;
    if ( not -s $reads_file ) {
        push @errors, UR::Object::Tag->create(
            type => 'invalid',
            properties => [qw/ assembly_directory /],
            desc => 'No input reads file found in assembly_directory:'.$self->assembly_directory,
        );
    }

    return @errors;
}

sub execute {
    my $self = shift;
    $self->status_message('Velvet metrics...');

    # input files
    my $resolve_assembly_files = $self->_validate_assembly_output_files;
    return if not $resolve_assembly_files;

    my $contigs_fa_file = $self->velvet_contigs_fa_file;
    # tier values
    my ($t1, $t2);
    if ($self->first_tier and $self->second_tier) {
        $t1 = $self->first_tier;
        $t2 = $self->second_tier;
    }
    else {
        my $est_genome_size = -s $contigs_fa_file;
        $t1 = int ($est_genome_size * 0.2);
        $t2 = int ($est_genome_size * 0.2);
    }
    $self->status_message('Tier one: 1 to '.$t1);
    $self->status_message('Tier two: '.$t1.' to '.($t1 + $t2));

    # metrics
    my $metrics = Genome::Model::Tools::Sx::Metrics::Assembly->create(
        major_contig_threshold => $self->major_contig_length,
        tier_one => $t1,
        tier_two => $t2,
    );
    $self->_metrics($metrics);

    # input reads
    my $reads_file = $self->input_collated_fastq_file;
    $self->status_message('Add reads file: '.$reads_file);
    my $add_reads = $metrics->add_reads_file_with_q20($reads_file);
    return if not $add_reads;

    # reads assembled
    $self->status_message('Add velvet afg file: '.$self->velvet_afg_file);
    my $add_read_depth = $self->_add_metrics_from_agp_file($metrics);
    return if not $add_read_depth;
    
    # transform metrics
    my $text = $metrics->transform_xml_to('txt');
    if ( not $text ) {
        $self->error_message('Failed to transform metrics to text!');
        return;
    }

    # write file
    my $output_file = $self->output_file;
    unlink $output_file if -e $output_file;
    $self->status_message('Write output file: '.$output_file);
    my $fh = eval{ Genome::Sys->open_file_for_writing($output_file); };
    if ( not $fh ) {
        $self->error_message('Failed to open metrics output file!');
        return;
    }
    #print $text;
    $fh->print($text);
    $fh->close;

    $self->status_message('Velvet metrics...DONE');
    return 1;
}

sub _validate_assembly_output_files {
    my $self = shift;
    # afg
    if ( not -s $self->velvet_afg_file ) {
        $self->error_message('No velvet_asm.afg file in assembly directory: '.$self->assembly_directory);
        return;
    }
    
    # Sequences
    if ( not -s $self->velvet_sequences_file ) {
        $self->error_message('No Sequences file in assembly dir: '.$self->assembly_directory);
        return;
    }

    # contig.fa
    if ( not -s $self->velvet_contigs_fa_file ) {
        $self->error_message('No contig.fa file in assembly dir: '.$self->assembly_directory);
        return;
    }
    return 1;
}

sub _add_metrics_from_agp_file { #for velvet assemblies
    my ($self, $metrics) = @_;

    my $afg_fh = eval{ Genome::Sys->open_file_for_reading($self->resolve_afg_file); };
    return if not $afg_fh;

    # read coverage
    my ($zero_x, $one_x, $two_x, $three_x, $four_x, $five_x ) = (qw/ 0 0 0 0 0 0 /);
    my ($total_contigs_length, $contigs_length_5k) = (0,0);

    #genome content
    my ( $gc_count, $at_count, $nx_count ) = ( 0,0,0 );

    my %uniq_reads;
    my $reads_assembled_in_scaffolds = 0;

    my $major_contigs_length = 0;
    my $minor_contigs_length = 0;
    my $major_contigs_read_count = 0;
    my $minor_contigs_read_count = 0;

    my $major_supercontigs_length = 0;
    my $minor_supercontigs_length = 0;

    my %reads_in_supercontigs;

    while (my $record = getRecord($afg_fh)) {
        my ($rec, $fields, $recs) = parseRecord($record);
        if ($rec eq 'CTG') {  #contig
            my $seq = $fields->{seq};
            $seq =~ s/\n//g; #contig seq is written in multiple lines

            my $contig_length = length $seq;
            $total_contigs_length += $contig_length;
            
            #contigs/supercontig lengths;
            my $contig_name = $fields->{eid};
            $metrics->{'contigs'}->{$contig_name} = $contig_length;
            my ($supercontig_name) = $fields->{eid} =~ /^(\d+)-/; 
            $metrics->{'supercontigs'}->{$supercontig_name} += $contig_length;

            #separate major/minor contigs metrics
            if ( $contig_length >= $self->major_contig_length ) {
                $major_contigs_length += $contig_length;
                $major_contigs_read_count += scalar @$recs;
            } else {
                $minor_contigs_length += $contig_length;
                $minor_contigs_read_count += scalar @$recs;
            }

            $reads_in_supercontigs{$supercontig_name} += scalar @$recs;

            #five k contig lengths
            $contigs_length_5k += $contig_length if $contig_length >= 5000;

            #genome contents
            my %base_counts = ( a => 0, t => 0, g => 0, C => 0, n => 0, x => 0 );
            foreach my $base ( split ('', $seq) ) {
                $base_counts{lc $base}++;
            }
            $gc_count += $base_counts{g} + $base_counts{c};
            $at_count += $base_counts{a} + $base_counts{t};
            $nx_count += $base_counts{n} + $base_counts{x};

            #read coverage 
            my @consensus_positions;
            for my $r (0..$#$recs) { #reads
                my ($srec, $sfields, $srecs) = parseRecord($recs->[$r]);

                #sfields
                #'src' => '19534',  #read id number
                #'clr' => '0,90',   #read start, stop 0,90 = uncomp 90,0 = comp
                #'off' => '75'      #read off set .. contig start position

                $reads_assembled_in_scaffolds++;
                $uniq_reads{$sfields->{src}}++;

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

                for ($left_pos .. $right_pos) {
                    $consensus_positions[$_]++;
                }
            }

            shift @consensus_positions; #remove [0] position 
            #
            if (scalar @consensus_positions < $contig_length) {
                $self->warning_message ("Covered consensus bases does not equal contig length\n\t".
                    "got ".scalar (@consensus_positions)." covered bases but contig length is $contig_length\n");
                $zero_x += ( $contig_length - scalar @consensus_positions );
            }
            foreach (@consensus_positions) {
                if ( not defined $_ ) { #not covered consensus .. probably an error in velvet afg file
                    $zero_x++;
                    next;
                }
                
                $one_x++   if $_ > 0;
                $two_x++   if $_ > 1;
                $three_x++ if $_ > 2;
                $four_x++  if $_ > 3;
                $five_x++  if $_ > 4;

            }
        }
    }

    $afg_fh->close;
    #genome content
    $metrics->set_metric('content_at', $at_count);
    $metrics->set_metric('content_gc', $gc_count);
    $metrics->set_metric('content_nx', $nx_count);

    #contigs lengths
    $metrics->set_metric('assembly_length', $total_contigs_length);
    $metrics->set_metric('contigs_length', $total_contigs_length);
    $metrics->set_metric('contigs_count', scalar ( keys %{$metrics->{'contigs'}} ));
    $metrics->set_metric('contigs_major_length', $major_contigs_length);
    $metrics->set_metric('contigs_minor_length', $minor_contigs_length);

    #supercontigs lengths
    $metrics->set_metric('supercontigs_length', $total_contigs_length);
    $metrics->set_metric('supercontigs_count', scalar ( keys %{$metrics->{'supercontigs'}} ));
    my $supercontigs_major_length = 0;
    my $supercontigs_minor_length = 0;
    for my $sctg ( keys %{$metrics->{'supercontigs'}} ) {
        my $length = $metrics->{'supercontigs'}->{$sctg};
        if ( $length >= $self->major_contig_length ) {
            $supercontigs_major_length += $length;
        } else {
            $supercontigs_minor_length += $length;
        }
    }
    $metrics->set_metric('supercontigs_major_length', $supercontigs_major_length);
    my $supercontigs_major_percent = ( $supercontigs_major_length > 0 ) ?
        sprintf( "%.1f", $supercontigs_major_length / $total_contigs_length * 100 )
        : 0 ;
    $metrics->set_metric('supercontigs_major_percent', $supercontigs_major_percent);
    $metrics->set_metric('supercontigs_minor_length', $supercontigs_major_length);

    #5k contig lengths
    $metrics->set_metric('contigs_length_5k', $contigs_length_5k);

    #reads assembled
    $metrics->set_metric('reads_assembled', $reads_assembled_in_scaffolds);
    my $reads_assembled_unique = keys %uniq_reads;
    $metrics->set_metric('reads_assembled_unique', $reads_assembled_unique);
    $metrics->set_metric('reads_assembled_duplicate', ($reads_assembled_in_scaffolds - $reads_assembled_unique));
    my $reads_count = $metrics->get_metric('reads_processed');
    my $reads_not_assembled = $reads_count - $reads_assembled_unique;
    $metrics->set_metric('reads_not_assembled', $reads_not_assembled);
    $metrics->set_metric('contigs_major_read_count', $major_contigs_read_count);
    my $contigs_major_read_percent = sprintf( "%.1f", $major_contigs_read_count / $reads_assembled_in_scaffolds * 100);
    $metrics->set_metric('contigs_major_read_percent', $contigs_major_read_percent);

    $metrics->set_metric('contigs_minor_read_count', $minor_contigs_read_count);
    my $contigs_minor_read_percent = sprintf( "%.1f", $minor_contigs_read_count / $reads_assembled_in_scaffolds * 100);
    $metrics->set_metric('contigs_minor_read_percent', $contigs_minor_read_percent);

    my $supercontigs_major_read_count = 0;
    my $supercontigs_minor_read_count = 0;
    for my $sctg ( keys %reads_in_supercontigs ) {
        if ( $metrics->{'supercontigs'}->{$sctg} >= $self->major_contig_length ) {
            $supercontigs_major_read_count += $reads_in_supercontigs{$sctg};
        } else {
            $supercontigs_minor_read_count += $reads_in_supercontigs{$sctg};
        }
    }
    $metrics->set_metric('supercontigs_major_read_count', $supercontigs_major_read_count);
    my $supercontigs_major_read_percent = sprintf( "%.1f", $supercontigs_major_read_count / $reads_assembled_in_scaffolds * 100);
    $metrics->set_metric('supercontigs_major_read_percent', $supercontigs_major_read_percent);
    $metrics->set_metric('supercontigs_minor_read_count', $supercontigs_minor_read_count);
    my $supercontigs_minor_read_percent = sprintf( "%.1f", $supercontigs_minor_read_count / $reads_assembled_in_scaffolds * 100);
    $metrics->set_metric('supercontigs_minor_read_percent', $supercontigs_minor_read_percent);

    #read coverage
    $metrics->set_metric('coverage_5x', $five_x);
    $metrics->set_metric('coverage_4x', $four_x);
    $metrics->set_metric('coverage_3x', $three_x);
    $metrics->set_metric('coverage_2x', $two_x);
    $metrics->set_metric('coverage_1x', $one_x);
    $metrics->set_metric('coverage_0x', $zero_x);

    return 1;
}

1;

