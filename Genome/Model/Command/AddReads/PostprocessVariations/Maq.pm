package Genome::Model::Command::AddReads::PostprocessVariations::Maq;

use strict;
use warnings;

use Genome::Model;
use Genome::Model::Command::Report::MetricsBatchToLsf;
use IO::File;
use File::Basename;

class Genome::Model::Command::AddReads::PostprocessVariations::Maq {
    is => ['Genome::Model::Command::AddReads::PostprocessVariations', 'Genome::Model::Command::MaqSubclasser'],
};

sub help_brief {
    "Create the input file required for the annotation report generators"
}

sub help_synopsis {
    return <<"EOS"
    genome-model add-reads postprocess-variations maq --model-id 5 --ref-seq-id 10
EOS
}

sub help_detail {                           
    return <<EOS 
Creates a file with SNP information used later by the annotation report pipeline.

The output file is tab separated and has these columns:
    chromosome_name
    start position
    end position (for SNPs, start and end will be equal)
    reference base
    sample base
    the string 'ref' to indicate the first base above is from the reference
    sample variation type ('SNP' for SNP data, later indel data will be something different)
    number of sample reads that match the reference
    number of sample reads that matched the indicated variant
    consensus quality at that position
    number of unique reads (by start position) covering that start position

If the sample is homozygous at the SNP position, only one line will be recorded.  If
the sample is heterozygous, there will be two lines with the same start position and
the same reference base.
EOS
}

sub bsub_rusage {
    return "-R 'select[type=LINUX64]'";
}

sub should_bsub { 1;}


sub _snp_resource_name {
    my $self = shift;
    return sprintf("snips%s", defined $self->ref_seq_id ? "_".$self->ref_seq_id : "");
}

sub _pileup_resource_name {
    my $self = shift;
    return sprintf("pileup%s", defined $self->ref_seq_id ? "_".$self->ref_seq_id : "");
}

sub _variation_metrics_name {
    my $self = shift;
    return sprintf("variation_metrics%s", defined $self->ref_seq_id ? "_".$self->ref_seq_id : "");
}

sub snp_output_file {
    my $self = shift;
    return sprintf("%s/identified_variations/%s", $self->model->data_directory,$self->_snp_resource_name);
}

sub pileup_output_file {
    my $self = shift;
    return sprintf("%s/identified_variations/%s", $self->model->data_directory,$self->_pileup_resource_name);
}

sub variation_metrics_file {
    my $self = shift;
    return sprintf("%s/identified_variations/%s", $self->model->data_directory, $self->_variation_metrics_name);
}

sub experimental_variation_metrics_file_basename {
    my $self = shift;
    return sprintf("%s/identified_variations/%s", $self->model->data_directory, 'experimental_' . $self->_variation_metrics_name);
}

sub execute {
    my $self = shift;
    my $model = $self->model;

    $self->revert;

    $DB::single=1;

    #unless ($self->generate_variation_metrics_files) {        
        #    $self->error_message("Error generating variation metrics file (used downstream at filtering time)!");
        # cleanup...
        #    return;
        #}

    unless ($self->generate_experimental_variation_metrics_files) {        
        $self->error_message("Error generating variation metrics file (used downstream at filtering time)!");
        return;
    }

    unless ($self->verify_successful_completion) {
        $self->error_message("Error validating results!");
        # cleanup...
        return;
    }
    
    return 1;
}

sub verify_successful_completion {
    my $self = shift;
    my $model = $self->model; 

    my $snp_output_file             = $self->snp_output_file;
    my $snp_output_file_count       = _wc($snp_output_file);
    
    my $errors = 0;
    
    my @ck = map { $self->$_ } qw/variation_metrics_file/;
    for my $ck (@ck) {
        unless (-e $ck) {
            $self->error_message("Failed to find $ck!");
            $errors++;
            next;
        }
        my $cnt = _wc($ck);
        unless ($cnt == $snp_output_file_count) {
            $self->error_message("File $ck has size $cnt "
                    . "while the SNP file $snp_output_file has size $snp_output_file_count!");
            $errors++;
        }
    }
    
    return !$errors;
}

sub _wc {
    my $name = shift;
    my $fh = IO::File->new($name);
    my $cnt = 0;
    while (<$fh>) { $cnt++ }
    return $cnt;
}

sub generate_variation_metrics_files {
    my $self = shift;

    my %p = @_;
    my $test_extension = $p{test_extension} || '';

    my $model = $self->model;
    my $ref_seq_id = $self->ref_seq_id;

    my $snpfile = $self->snp_output_file;
    my $variation_metrics_file = $self->variation_metrics_file.$test_extension;

    my $parallel_units;
    if ($ref_seq_id == 1 or $ref_seq_id == 8 or $ref_seq_id == 10) {
        $parallel_units = 1;
    }
    elsif ($ref_seq_id < 10) {
        $parallel_units = 1;
    }
    else {
        $parallel_units = 1;
    }

    my @libraries = $model->libraries;

    #TODO: let the filtering module indicate whether it requires per-library metrics.
    my @check_libraries;
    if ($model->filter_ruleset_name eq 'dtr3e' or $model->filter_ruleset_name eq 'dtr2a') {
        @check_libraries = (@libraries,'');
        $self->status_message("\n*** Generating per-library metric breakdown of $variation_metrics_file");
        $self->status_message(join("\n",map { "'$_'" } @libraries));
    }
    else {
        @check_libraries = ('');
    }

    foreach my $library_name (@check_libraries) {
        my $variation_metrics_file = $self->variation_metrics_file;

        my $chromosome_alignment_file;
        if ($library_name) {
            $variation_metrics_file .= '.' . $library_name.$test_extension;
            $self->status_message("\n...generating per-library metrics for $variation_metrics_file");
        }
        else {
            $variation_metrics_file .= $test_extension;
            $self->status_message("\n*** Generating cross-library metrics for $variation_metrics_file");
        }    
    
        my $tries = 0;
        for (1) {
            if ($library_name) {
                $chromosome_alignment_file = $self->resolve_accumulated_alignments_filename(
                    ref_seq_id => $self->ref_seq_id,
                    library_name => $library_name,
                );
            }
            else {
                $chromosome_alignment_file = $self->resolve_accumulated_alignments_filename(
                    ref_seq_id => $self->ref_seq_id,
                );
            }    
            
            unless (
                $chromosome_alignment_file 
                and -e $chromosome_alignment_file 
                and (-p $chromosome_alignment_file or -s $chromosome_alignment_file)
            ) {
                $self->error_message(
                    "Failed to create an accumulated alignments file for"
                    . ($library_name ? " library_name '$library_name' " : '')
                    . " ref_seq_id " . $self->ref_seq_id    
                    . " to generate metrics file $variation_metrics_file"
                );
                if ($tries > 3) {
                    return;
                }
                else {
                    redo;
                }
            }
        }
        
        my $result =
            Genome::Model::Tools::Maq::GenerateVariationMetrics->execute(
                input => $chromosome_alignment_file,
                snpfile => $snpfile,
                qual_cutoff => 1,
                output => $variation_metrics_file,
                parallel_units => $parallel_units,
            );

        unless ($result) {
            $self->error_message("Failed to generate cross-library metrics for $variation_metrics_file");
            return;
        }

        unless (-s ($variation_metrics_file)) {
            $self->error_message("Metrics file not found for library $variation_metrics_file!");
            return;
        }
    }

    return 1;
}

sub generate_experimental_variation_metrics_files {
    # This generates additional bleeding-edge data.
    # It runs directly out of David Larson's home for now until merged w/ the stuff above.
    # It will be removed when bugs are worked out in the regular metric generator.

    my $self = shift;

    my $output_basename     = $self->experimental_variation_metrics_file_basename;
    
    my $snp_file            = $self->snp_output_file;
    my $ref_seq             = $self->ref_seq_id;
    my $map_file            = $self->resolve_accumulated_alignments_filename(ref_seq_id => $self->ref_seq_id); 
    
    my $model = $self->model;
    my $bfa_file = sprintf("%s/all_sequences.bfa", $model->reference_sequence_path);

    my @f = ($map_file,$bfa_file,$snp_file);
    my $errors = 0;
    for my $f (@f) {
        if (-e $f) {
            $self->status_message("Found file $f");
        }
        else {
            $self->error_message("Failed to find file $f");
            $errors++;
        }
    }
    return if $errors;
    my $cmd = "perl /gscuser/dlarson/pipeline_mapstat/snp_stats.pl --mapfile $map_file --ref-bfa $bfa_file --basename 'extra_metrics_$ref_seq' --locfile $snp_file --minq 1 --chr=$ref_seq";
    my $result = system($cmd);
    $result /= 256;
    return $result;
}

# Converts between the 1-letter genotype code into
# its allele constituients
sub _lookup_iub_code {
    my($self,$code) = @_;

    $self->{'_iub_code_table'} ||= {
             A => ['A', 'A'],
             C => ['C', 'C'],
             G => ['G', 'G'],
             T => ['T', 'T'],
             M => ['A', 'C'],
             K => ['G', 'T'],
             Y => ['C', 'T'],
             R => ['A', 'G'],
             W => ['A', 'T'],
             S => ['G', 'C'],
             D => ['A', 'G', 'T'],
             B => ['C', 'G', 'T'],
             H => ['A', 'C', 'T'],
             V => ['A', 'C', 'G'],
             N => ['A', 'C', 'G', 'T'],
          };
    return @{$self->{'_iub_code_table'}->{$code}};
}


# Given a fh to a whole-lane map file, return a count of the number of 
# unique reads (by start position) for a given position. 
# If two reads have the same start position, it considers them the same
# if the first 26 bases are the same
sub unique_reads_at_position {
    my($self,$map_fh,$pos) = @_;

    my $last_pos = $self->{'_last_map_pos'} || 0;
    while ($last_pos <= $pos) {
        my $line = $map_fh->getline();
        my @line = split("\t",$line);

        my $start_pos = $line[2];
        $last_pos = $start_pos;
        my $readlen = length($line[14]);   # column 14 is the read data
        my $end_pos = $start_pos + $readlen;
        next if ($end_pos < $pos);   # This read ended before the point we're interested in

        my $sub_sequence;
        if ($readlen > 26) {
            # Quality really drops off after the first 26 bases, so only do our
            # comparisons among those

            if ($line[3] eq '-') {    # 3rd column is the strand 
                # start position is always from the point of view of the forward direction, so
                # for reads on the reverse strand, we need to take the last 26 bases instead of the
                # first 26, and alter the start position to point to the 26th base (from the reverse
                # direction)
                $sub_sequence = uc(substr($line[14], 0, -26));
                $start_pos += ($readlen - 26);
            } else {
                $sub_sequence = uc(substr($line[14], 0, 26));
            }
        } else {
            $sub_sequence = $line[14];
        }

        if (! $self->{'_map_cache_end_pos'}->{$start_pos}) {
            # Haven't had a read at this start pos yet
            $self->{'_map_cache_end_pos'}->{$start_pos} = [ $end_pos ];
            $self->{'_map_cache_sub_sequence'}->{$start_pos} = [ $sub_sequence ];
            $self->{'_map_cache_count'}++;

        } else {
            my $matched = 0;
            # Does the first 26 bases of this read match any of the other 26 bases at this start pos?
            for (my $i = 0; $i < @{$self->{'_map_cache_sub_sequence'}->{$start_pos}}; $i++) {
                if ( $sub_sequence eq $self->{'_map_cache_sub_sequence'}->{$start_pos}->[$i] ) {
                    $matched = 1;
                    last;
                }
            }
            unless ($matched) {
                push @{$self->{'_map_cache_end_pos'}->{$start_pos}}, $end_pos;
                push @{$self->{'_map_cache_sub_sequence'}->{$start_pos}}, $sub_sequence;
                $self->{'_map_cache_count'}++;
            }
        }
    }

    $self->{'_last_map_pos'} = $last_pos;

    # remove any positions that have left the window
    foreach my $key ( keys %{$self->{'_map_cache_end_pos'}} ) {
        next if ($self->{'_map_cache_end_pos'}->{$key} >= $pos);
        delete($self->{'_map_cache_end_pos'}->{$key});
        delete($self->{'_map_cache_sub_sequence'}->{$key});
        $self->{'_map_cache_count'}--;
    }

    # Subtract 1 because we've read in one record past the position we asked for
    return $self->{'_map_cache_count'} - 1;
}

#- LOG FILES -#
sub snp_out_log_file {
    my $self = shift;

    return sprintf
    (
        '%s/%s.out', #'%s/%s_snp.out',
        $self->resolve_log_directory,
        ($self->lsf_job_id || $self->ref_seq_id),
    );
}

sub snp_err_log_file {
    my $self = shift;

    return sprintf
    (
        '%s/%s.err', #'%s/%s_snp.err',
        $self->resolve_log_directory,
        ($self->lsf_job_id || $self->ref_seq_id),
    );
}

1;

