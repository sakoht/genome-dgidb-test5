package Genome::Model::ReadSet;

use strict;
use warnings;
use YAML;

use Genome;

class Genome::Model::ReadSet {
    table_name => 'GENOME_MODEL_READ_SET',
    id_by => [
        model               => { is => 'Genome::Model', id_by => 'model_id', constraint_name => 'GMRSET_GM_PK ' },
        read_set            => { is => 'Genome::RunChunk', id_by =>'read_set_id'},
    ],
    has => [   
        first_build_id      => { is => 'NUMBER', len => '10', is_optional=>1 }, 
        alignment_directory => { via => 'model'},
        run_name            => { via => 'read_set'},
            # PICK ONE AND FIX EVERYTHING THAT USES THIS
        subset_name         => { via => 'read_set'},
        run_subset_name     => { via => 'read_set', to => 'subset_name'},
            # PICK ONE AND FIX EVERYTHING THAT USES THIS
        short_name          => { via => 'read_set' },
        run_short_name      => { via => 'read_set', to => 'short_name' },
        library_name        => { via => 'read_set' },
        sample_name         => { via => 'read_set' },
        sequencing_platform => { via => 'read_set' },
        full_path           => { via => 'read_set' },
        unique_reads_across_library     => { via => 'read_set' },
        duplicate_reads_across_library  => { via => 'read_set' },
        median_insert_size => {via => 'read_set'},
        sd_above_insert_size => {via => 'read_set'},
        is_paired_end => {via => 'read_set' },
 
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

sub sample_data_directory {
    my $self = shift;
    return $self->full_path .'/'. $self->sample_name;
}

sub read_set_data_directory {
    my $self = shift;
    return $self->sample_data_directory .'/'. $self->run_name .'/'. $self->subset_name;
}

sub read_set_alignment_directory {
    my $self = shift;

    return sprintf('%s/%s/%s_%s',
                       $self->alignment_directory,
                       $self->run_name,
                       $self->subset_name,
                       $self->read_set_id
                  );
}

sub new_read_set_alignment_directory {
    my $self=shift;
    return sprintf('%s/%s/%s/%s',
                       $self->alignment_directory,
                       $self->sample_name,
                       $self->run_name,
                       $self->subset_name,
                  );
}

sub invalid {
    my ($self) = shift;

    my @tags = $self->SUPER::invalid(@_);
    unless (Genome::Model->get($self->model_id)) {
        push @tags, UR::Object::Tag->create(
                                            type => 'invalid',
                                            properties => ['model_id'],
                                            desc => "There is no model with id ". $self->model_id,
                                        );
    }

    unless (Genome::RunChunk->get(id => $self->read_set_id)) {
        push @tags, UR::Object::Tag->create(
                                            type => 'invalid',
                                            properties => ['read_set_id'],
                                            desc => "There is no genome run with id ". $self->read_set_id,
                                        );
    }
    return @tags;
}

sub alignment_file_paths {
    my $self=shift;
    return unless -d $self->read_set_alignment_directory;
   return grep { -e $_ && $_ !~ /aligner_output/ } glob($self->read_set_alignment_directory .'/*'. '*.map*');
}
sub aligner_output_file_paths {
    my $self=shift;
    return unless -d $self->read_set_alignment_directory;
    return grep { -e $_ } glob($self->read_set_alignment_directory .'/*'. '.map.aligner_output.*');
}
sub poorly_aligned_reads_list_paths {
    my $self=shift;
    return unless -d $self->read_set_alignment_directory;
    return grep { -e $_ } grep { $_ !~ /\.fastq$/ } glob($self->read_set_alignment_directory .'/*'.
                                                         $self->subset_name .'_sequence.unaligned.*');
}
sub poorly_aligned_reads_fastq_paths  {
    my $self=shift;
    return unless -d $self->read_set_alignment_directory;
    return grep { -e $_ } glob($self->read_set_alignment_directory .'/*'.
                               $self->subset_name .'_sequence.unaligned.*.fastq');
}
sub contaminants_file_path {
    my $self=shift;
    return unless -d $self->read_set_alignment_directory;
    return grep { -e $_ } glob($self->read_set_alignment_directory .'/adaptor_sequence_file');
}
sub read_length {
    my $self=shift;
    if ($self->read_set->read_length <= 0) {
        die('Impossible value for read_length field. seq_id:'. $self->read_set->seq_id);
    }
    return $self->read_set->read_length;
}
sub _calculate_total_read_count {
    my $self = shift;
    if ($self->read_set->clusters <= 0) {
        die('Impossible value for clusters field. seq_id:'. $self->read_set->seq_id);
    }
    return $self->read_set->clusters;
}

sub read_set_alignment_files_for_refseq {
    # this returns the above, or will return the old-style split maps
    my $self = shift;
    my $ref_seq_id = shift;
    my $read_set = $self->read_set;
    my $alignment_dir = $self->read_set_alignment_directory;

    # Look for files in the new format: $refseqid.map.$eventid
    my @files = grep { $_ and -e $_ } (
        glob($self->read_set_alignment_directory . "/$ref_seq_id.map.*") #bkward compat
    );
    return @files if (@files);

    # Now try the old format: $refseqid_{unique,duplicate}.map.$eventid
    my $glob_pattern = sprintf('%s/%s_*.map.*', $alignment_dir, $ref_seq_id);
    @files = grep { $_ and -e $_ } (
        glob($glob_pattern)
    );
    return @files;
}

sub yaml_string {
    my $self = shift;
    return YAML::Dump($self);
}

sub get_alignment_statistics {
    my $self=shift;
    #this method will eventually populate the metrics table but for now it populates dave larson 
    my ($aligner_output_file) = $self->aligner_output_file_paths;

    my $fh = IO::File->new($aligner_output_file);
    unless($fh) {
        $self->error_message("unable to open maq's alignment output file:  " . $aligner_output_file);
        return;
    }
    my @lines = $fh->getlines;
    $fh->close;

    my ($line_of_interest)=grep { /total, isPE, mapped, paired/ } @lines;
    my ($comma_separated_metrics) = ($line_of_interest =~ m/= \((.*)\)/);
    my @values = split(/,\s*/,$comma_separated_metrics);
    my %hashy_hash_hash;
    $hashy_hash_hash{total}=$values[0];
    $hashy_hash_hash{isPE}=$values[1];
    $hashy_hash_hash{mapped}=$values[2];
    $hashy_hash_hash{paired}=$values[3];
    return \%hashy_hash_hash;
}

1;
