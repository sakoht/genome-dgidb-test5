package Genome::InstrumentData::Imported;

#REVIEW fdu 11/17/2009
#More methods could be implemented for calculating metrics and
#resolving file path with Imported-based models soon in use

use strict;
use warnings;

use Genome;
use File::stat;

class Genome::InstrumentData::Imported {
    is => [ 'Genome::InstrumentData' ],
    type_name => 'imported instrument data',
    table_name => 'IMPORTED_INSTRUMENT_DATA',
    subclassify_by => 'subclass_name',
    id_by => [
        id => {  },
    ],
    has => [
        import_date          => { is => 'DATE', len => 19 },
        user_name            => { is => 'VARCHAR2', len => 256 },
        sample_id            => { is => 'NUMBER', len => 20 },
        original_data_path   => { is => 'VARCHAR2', len => 256 },
        sample_name          => { is => 'VARCHAR2', len => 64, is_optional => 1 },
        import_source_name   => { is => 'VARCHAR2', len => 64, is_optional => 1 },
        import_format        => { is => 'VARCHAR2', len => 64, is_optional => 1 },
        sequencing_platform  => { is => 'VARCHAR2', len => 64, is_optional => 1 },
        description          => { is => 'VARCHAR2', len => 512, is_optional => 1 },
        read_count           => { is => 'NUMBER', len => 20, is_optional => 1 },
        base_count           => { is => 'NUMBER', len => 20, is_optional => 1 },
        disk_allocations     => { is => 'Genome::Disk::Allocation', reverse_as => 'owner', where => [ allocation_path => {operator => 'like', value => '%imported%'} ], is_optional => 1, is_many => 1 },
        fragment_count       => { is => 'NUMBER', len => 20, is_optional => 1 },
        fwd_read_length      => { is => 'NUMBER', len => 20, is_optional => 1 },
        is_paired_end        => { is => 'NUMBER', len => 1, is_optional => 1 },
        median_insert_size   => { is => 'NUMBER', len => 20, is_optional => 1 },
        read_length          => { is => 'NUMBER', len => 20, is_optional => 1 },
        rev_read_length      => { is => 'NUMBER', len => 20, is_optional => 1 },
        run_name             => { is => 'VARCHAR2', len => 255, is_optional => 1 },
        sd_above_insert_size => { is => 'NUMBER', len => 20, is_optional => 1 },
        subset_name          => { is => 'VARCHAR2', len => 255, is_optional => 1 },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

sub data_directory {
    my $self = shift;

    my $alloc = $self->get_disk_allocation;

    if ($alloc) {
        return $alloc->absolute_path;
    }

}

# TODO: remove me and use the actual object accessor
sub get_disk_allocation {
    my $self = shift;
    return $self->disk_allocation;
}

sub calculate_alignment_estimated_kb_usage {
    my $self = shift;
    my $answer;
    if($self->original_data_path !~ /\,/ ) {
        if (-d $self->original_data_path) {
            my $du_source = "du -sb ".$self->original_data_path;
            my $s_size = qx/ $du_source /;
            my @source_size = split(' ', $s_size);
            $answer = ($source_size[0]/1000)+ 100;
        } else {
            my $stat = stat($self->original_data_path);
            $answer = ($stat->size/1000) + 100; 
        } 
    }
    else {
        my @files = split /\,/  , $self->original_data_path;
        my $stat;
        my $size;
        foreach (@files) {
            if (-s $_) {
                $stat = stat($_);
                $size += $stat->size;
            } else {
                die "file not found - $_\n";
            }
        }
        $answer = ($size/1000) + 100;
    }
    return int($answer);
}


sub create {
    my $class = shift;
    
    my %params = @_;
    my $user   = getpwuid($<); 
    my $date   = UR::Time->now;

    $params{import_date} = $date;
    $params{user_name}   = $user; 

    my $self = $class->SUPER::create(%params);

    return $self;
}

################## Solexa Only ###################

*fastq_filenames = \&Genome::InstrumentData::Solexa::fastq_filenames;
*dump_illumina_fastq_archive = \&Genome::InstrumentData::Solexa::dump_illumina_fastq_archive;
*resolve_fastq_filenames = \&Genome::InstrumentData::Solexa::resolve_fastq_filenames;

sub total_bases_read {
    my $self = shift;
    return ($self->fwd_read_length + $self->rev_read_length) * $self->fragment_count;
}

# leave as-is for first test, 
# ultimately find out what uses this and make sure it really wants clusters
sub _calculate_total_read_count {
    my $self = shift;
    return $self->fragment_count;
}

# rename everything which uses this to fragment_count instead of read_count
# DB: (column name is "fragment_count"
#sub fragment_count { 10_000_000 }

sub clusters { shift->fragment_count}

sub flow_cell_id {
    my $self = shift;
    $self->id;
}

sub library_name {
    my $self = shift;
    $self->id;
}

sub lane {
    my $self = shift;
    return $self->subset_name;
}

sub run_start_date_formatted {
    UR::Time->now();
}

sub seq_id {
    my $self = shift;
    return $self->id;
}

sub instrument_data_id {
    my $self = shift;
    return $self->id;
}

sub resolve_quality_converter {
    'sol2phred'
}

sub gerald_directory {
    undef;
}

sub desc {
    my $self = shift;
    return $self->description;
}

sub is_external {
    0;
}

sub resolve_adaptor_file {
 return '/gscmnt/sata114/info/medseq/adaptor_sequences/solexa_adaptor_pcr_primer';
}

# okay for first test, before committing switch to getting the allocation and returning the path under it
sub archive_path {
    my $self = shift;
    
    $self->disk_allocations->absolute_path;
}

1;
