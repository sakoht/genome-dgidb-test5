package Genome::InstrumentData::Imported;

#REVIEW fdu 11/17/2009
#More methods could be implemented for calculating metrics and
#resolving file path with Imported-based models soon in use

use strict;
use warnings;

use Genome;
use File::stat;
use File::Path;

class Genome::InstrumentData::Imported {
    is => [ 'Genome::InstrumentData','Genome::Utility::FileSystem' ],
    type_name => 'imported instrument data',
    table_name => 'IMPORTED_INSTRUMENT_DATA',
    subclassify_by => 'subclass_name',
    id_by => [
        id => {  },
    ],
    has => [
        import_date          => { is => 'DATE', len => 19 },
        user_name            => { is => 'VARCHAR2', len => 256 },
        original_data_path   => { is => 'VARCHAR2', len => 1000 },
        import_format        => { is => 'VARCHAR2', len => 64 },
        sequencing_platform  => { is => 'VARCHAR2', len => 64 },
        import_source_name   => { is => 'VARCHAR2', len => 64, is_optional => 1 },
        description          => { is => 'VARCHAR2', len => 512, is_optional => 1 },
        read_count           => { is => 'NUMBER', len => 20, is_optional => 1 },
        base_count           => { is => 'NUMBER', len => 20, is_optional => 1 },
        disk_allocations     => { is => 'Genome::Disk::Allocation', reverse_as => 'owner', where => [ allocation_path => { operator => 'like', value => '%imported%' }  ], is_optional => 1, is_many => 1 },
        fragment_count       => { is => 'NUMBER', len => 20, is_optional => 1 },
        fwd_read_length      => { is => 'NUMBER', len => 20, is_optional => 1 },
        is_paired_end        => { is => 'NUMBER', len => 1, is_optional => 1 },
        median_insert_size   => { is => 'NUMBER', len => 20, is_optional => 1 },
        read_length          => { is => 'NUMBER', len => 20, is_optional => 1 },
        rev_read_length      => { is => 'NUMBER', len => 20, is_optional => 1 },
        run_name             => { is => 'VARCHAR2', len => 255, is_optional => 1 },
        sd_above_insert_size => { is => 'NUMBER', len => 20, is_optional => 1 },
        subset_name          => { is => 'VARCHAR2', len => 255, is_optional => 1 },
        target_region_set_name => { is => 'VARCHAR2', len => 64, is_optional => 1 },
        library_id           => { is => 'NUMBER', len => 20, is_optional => 0 },
        _old_sample_name      => { is => 'VARCHAR2', len => 20, is_optional => 1, column_name=>'SAMPLE_NAME' },
        _old_sample_id        => { is => 'NUMBER', len => 20, is_optional => 1, column_name=>'SAMPLE_ID' },
    ],
    has_optional =>[
        reference_sequence_build_id => { 
            via => 'attributes', 
            to => 'value', 
            is_mutable => 1, 
            where => [ 
                property_name => 'reference_sequence_build', 
                entity_class_name => 'Genome::InstrumentData::Imported', 
            ],
        },
        sra_accession => { 
            via => 'attributes', 
            to => 'value', 
            is_mutable => 1, 
            where => [ 
                property_name => 'sra_accession', 
                entity_class_name => 'Genome::InstrumentData::Imported', 
            ],
        },
        sra_sample_id => { 
            via => 'attributes', 
            to => 'value', 
            is_mutable => 1, 
            where => [ 
                property_name => 'sra_sample_id', 
                entity_class_name => 'Genome::InstrumentData::Imported', 
            ],
        },
    ],
    has_many_optional => [
        attributes => { is => 'Genome::MiscAttribute', reverse_as => '_instrument_data', where => [ entity_class_name => 'Genome::InstrumentData::Imported' ] },
    ],

    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

sub __display_name__ {
    my $self = $_[0];
    return (
        join(' ', map { $self->$_ } qw/sequencing_platform import_format id/)
        . ($self->desc ? ' (' . $self->desc . ')' : '')
    );
}

sub data_directory {
    my $self = shift;

    my $alloc = $self->get_disk_allocation;

    if (defined($alloc)) {
        return $alloc->absolute_path;
    } else {
        $self->error_message("Could not find an associated disk_allocations record.");
        die $self->error_message;
    }

}

# TODO: remove me and use the actual object accessor
sub get_disk_allocation {
    my $self = shift;
    return $self->disk_allocations;
}

sub calculate_alignment_estimated_kb_usage {
    my $self = shift;
    my $answer;
    if($self->original_data_path !~ /\,/ ) {
        if (-d $self->original_data_path) {
            my $source_size = Genome::Utility::FileSystem->directory_size_recursive($self->original_data_path);
            $answer = ($source_size/1000)+ 100;
        } else {
            unless ( -e $self->original_data_path) {
                $self->error_message("Could not locate directory or file to import.");
                die $self->error_message;
            }
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

    $self->_old_sample_id($self->sample_id);

    return $self;
}

sub delete {
    my $self = shift;
    my @allocations = Genome::Disk::Allocation->get(owner => $self);
    if (@allocations) {
        UR::Context->create_subscription(
            method => 'commit', 
            callback => sub {
                for my $allocation (@allocations) {
                    my $id = $allocation->id;
                    print 'Now deleting allocation with owner_id = ' . $id . "\n";
                    my $path = $allocation->absolute_path;
                    unless (rmtree($path)) {
                        print STDERR "ERROR: could not rmtree $path\n";
                        return;
                    }
                    $allocation->deallocate; 
                    print "Deletion complete.\n";
                }
                return 1;
            }
        );
    }
    return $self->SUPER::delete(@_);
}

################## Solexa Only ###################
# aliasing these methods before loading Genome::InstrumentData::Solexa causes it to 
# believe Genome::InstrumentData::Solexa is already loaded.  So we load it first...
##################################################
BEGIN: {
Genome::InstrumentData::Solexa->class;
*solexa_dump_sanger_fastq_files= \&Genome::InstrumentData::Solexa::dump_sanger_fastq_files;
*dump_illumina_fastq_files= \&Genome::InstrumentData::Solexa::dump_illumina_fastq_files;
*dump_solexa_fastq_files= \&Genome::InstrumentData::Solexa::dump_solexa_fastq_files;
*dump_illumina_fastq_archive = \&Genome::InstrumentData::Solexa::dump_illumina_fastq_archive;
*_unprocessed_fastq_filenames= \&Genome::InstrumentData::Solexa::_unprocessed_fastq_filenames;
*validate_fastq_directory = \&Genome::InstrumentData::Solexa::validate_fastq_directory;
*resolve_fastq_filenames = \&Genome::InstrumentData::Solexa::resolve_fastq_filenames;
*fragment_fastq_name = \&Genome::InstrumentData::Solexa::fragment_fastq_name;
*read1_fastq_name = \&Genome::InstrumentData::Solexa::read1_fastq_name;
*read2_fastq_name = \&Genome::InstrumentData::Solexa::read2_fastq_name;
}

sub dump_sanger_fastq_files {
    my $self = shift;

    if ($self->import_format eq 'bam') {
        return $self->dump_fastqs_from_bam(@_);
    } else {
        return $self->solexa_dump_sanger_fastq_files(@_);
    }
}

sub dump_fastqs_from_bam {
    my $self = shift;
    my $temp_dir = Genome::Utility::FileSystem->create_temp_directory('unpacked_bam');

    my $subset = (defined $self->subset_name ? $self->subset_name : 0);

    my $fwd_file = sprintf("%s/s_%s_1_sequence.txt", $temp_dir, $subset);
    my $rev_file = sprintf("%s/s_%s_2_sequence.txt", $temp_dir, $subset);
    my $fragment_file = sprintf("%s/s_%s_sequence.txt", $temp_dir, $subset);
    my $cmd = Genome::Model::Tools::Picard::SamToFastq->create(input=>$self->data_directory . "/all_sequences.bam", fastq=>$fwd_file, fastq2=>$rev_file, fragment_fastq=>$fragment_file);
    unless ($cmd->execute()) {
        die $cmd->error_message;
    }

    if ((-s $fwd_file && !-s $rev_file) ||
        (!-s $fwd_file && -s $rev_file)) {
        $self->error_message("Fwd & Rev files are lopsided; one has content and the other doesn't. Can't proceed"); 
        die $self->error_message;
    }

    my @files;
    if (-s $fwd_file && -s $rev_file) { 
        push @files, ($fwd_file, $rev_file);
    }
    if (-s $fragment_file) {
        push @files, $fragment_file;
    }
   
    return @files; 
}


sub total_bases_read {
    my $self = shift;
    
    my $fwd_read_length = $self->fwd_read_length || 0;
    my $rev_read_length = $self->rev_read_length || 0;
    my $fragment_count = $self->fragment_count || 0;
    unless(defined($self->fragment_count)){
        return undef;
    }
    return ($fwd_read_length + $rev_read_length) * $fragment_count;
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

sub run_name {
    my $self= shift;
    if($self->__run_name) {
        return $self->__run_name;
    }
    return $self->id;
}

sub short_run_name {
    my $self = shift;
    unless($self->run_name eq $self->id){
        my (@names) = split('-',$self->run_name);
        return $names[-1];
    }
    return $self->run_name;
}

sub flow_cell_id {
    my $self = shift;
    return $self->short_run_name;
}

sub library_name {
    my $self = shift;
    unless ($self->library_id) {
        return $self->id;
    }
    
    return Genome::Library->get($self->library_id)->name;
}

sub lane {
    my $self = shift;
    my $subset_name = $self->subset_name;
    if ($subset_name =~/[-\.]/){
        my ($lane) = $subset_name =~ /(\d)[-\.]/;
        return $lane;
    }else{
        return $subset_name;
    }
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
    my $self = shift;

    if ($self->import_format eq "solexa fastq") {
        return 'sol2sanger';
    } elsif ($self->import_format eq "illumina fastq") {
        return 'sol2phred';
    } elsif ($self->import_format eq 'sanger fastq') {
        return 'none';
    } else {
        $self->error_message("cannot resolve quality convertor for import format of type " . $self->import_format);
        die $self->error_message;
    }
}

sub gerald_directory {
    undef;
}

sub desc {
    my $self = shift;
    return $self->description || "[unknown]";
}

sub is_external {
    0;
}

sub resolve_adaptor_file {
 return '/gscmnt/sata114/info/medseq/adaptor_sequences/solexa_adaptor_pcr_primer';
}

sub run_identifier {
 my $self = shift;
 return $self->id;
}

sub _archive_file_name { # private for now...can be public
    my $self = shift;

    my $format = $self->import_format;
    if ( $format =~ /fastq/ ){
        return 'archive.tgz';
    }
    elsif ( $format eq 'bam' ){
        return 'all_sequences.bam';
    }
    elsif ( $format eq 'sff' ){
        return 'all_sequences.sff';
    }
    else {
        Carp::confess("Unknown import format: $format");
    }
}

sub archive_path {
    my $self = shift;

    my $alloc = $self->disk_allocations;
    return if not $alloc;

    my $file_name = $self->_archive_file_name;
    return $alloc->absolute_path.'/'.$file_name;
}

1;
