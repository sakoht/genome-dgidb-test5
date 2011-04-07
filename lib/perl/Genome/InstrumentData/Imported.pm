package Genome::InstrumentData::Imported;

use strict;
use warnings;

use Genome;
use File::stat;
use File::Path;

class Genome::InstrumentData::Imported {
    is => 'Genome::InstrumentData',
    has_optional => [
        import_date => {
            is => 'DateTime',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'import_date' ],
        },
        user_name => {
            is => 'Text',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'user_name' ],
        },
        original_data_path => {
            is => 'DirectoryPath',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'original_data_path' ],
        },
        import_format => {
            is => 'Text',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'import_format' ],
        },
        import_source_name => {
            is => 'Text',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'import_source_name' ],
        },
        description => {
            is => 'Text',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'description' ],
        },
        read_count => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'read_count' ],
        },
        base_count => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'base_count' ],
        },
        fragment_count => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'fragment_count' ],
        },
        fwd_read_length => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'fwd_read_length' ],
        },
        is_paired_end => {
            is => 'Boolean',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'is_paired_end' ],
        },
        median_insert_size => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'median_insert_size' ],
        },
        read_length => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'read_length' ],
        },
        rev_read_length => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'rev_read_length' ],
        },
        sd_above_insert_size => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'sd_above_insert_size' ],
        },
        target_region_set_name => {
            is => 'Text',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'target_region_set_name' ],
        },
        sra_accession => {
            is => 'Text',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'sra_accession' ],
        },
        sra_sample_id => {
            is => 'Text',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'sra_sample_id' ],
        },
        reference_sequence_build_id => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'reference_sequence_build_id' ],
        },
        reference_sequence_build => {
            is => 'Genome::Model::Build::ImportedReferenceSequence',
            id_by => 'reference_sequence_build_id',
        },
        disk_allocations => { is => 'Genome::Disk::Allocation', reverse_as => 'owner', is_many => 1 },
        bam_path => { calculate => q|my $f = $self->disk_allocations->absolute_path . '/all_sequences.bam';  return $f if (-e $f);| },
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

sub run_name {
    my $self = shift;
    return $self->{run_name} if defined $self->{run_name};
    return $self->id;
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

    # Check for an existing allocation for this instrument data, which would've been created by the importer
    my $allocation = Genome::Disk::Allocation->get(owner_class_name => $self->class, owner_id => $self->id);
    if ($allocation) {
        return int(($allocation->kilobytes_requested/1000) + 100);
    }

    if($self->original_data_path !~ /\,/ ) {
        if (-d $self->original_data_path) {
            my $source_size = Genome::Sys->directory_size_recursive($self->original_data_path);
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
    
    unless (exists $params{import_date}) {
        my $date = UR::Time->now;
        $params{import_date} = $date;
    }
    unless (exists $params{user_name}) {
        my $user = getpwuid($<); 
        $params{user_name} = $user; 
    }

    my $self = $class->SUPER::create(%params);
    return $self;
}

sub delete {
    my $self = shift;

    my @alignment_results = Genome::InstrumentData::AlignmentResult->get(instrument_data_id => $self->id);
    if (@alignment_results) {
        $self->error_message("Cannot remove instrument data (" . $self->id . ") because it has " . scalar @alignment_results . " alignment result(s).");
        return;
    }

    my @allocations = Genome::Disk::Allocation->get(owner => $self);
    if (@allocations) {
        UR::Context->create_subscription(
            method => 'commit', 
            callback => sub {
                for my $allocation (@allocations) {
                    my $id = $allocation->id;
                    print 'Now deleting allocation with owner_id = ' . $id . "\n";
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
no warnings 'once';
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
*dump_trimmed_fastq_files = \&Genome::InstrumentData::Solexa::dump_trimmed_fastq_files;
}

sub dump_sanger_fastq_files {
    my $self = shift;

    if ($self->import_format eq 'bam') {
        return $self->dump_fastqs_from_bam(@_);
    } else {
        return $self->solexa_dump_sanger_fastq_files(@_);
    }
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

sub lane {
    my $self = shift;
    my $subset_name = $self->subset_name;
    if ($subset_name =~ m/DACC/ && $subset_name =~/[-\.]/){
        my ($lane) = $subset_name =~ /(\d)[-\.]/;
        return $lane;
    }else{
        return $subset_name;
    }
}

sub run_start_date_formatted {
    return Genome::Model::Tools::Sam->time();
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

sub get_segments {
    my $self = shift;
    
    unless ($self->import_format eq "bam") {
        return ();
    }
    
    my ($allocation) = $self->disk_allocations;
    unless ($allocation) {
        $self->error_message("Found no disk allocation for imported instrument data " . $self->id, ", so cannot find bam!");
        die $self->error_message;
    }

    my $bam_file = $allocation->absolute_path . "/all_sequences.bam";
    
    unless (-e $bam_file) {
        $self->error_message("Bam file $bam_file doesn't exist, can't get segments for it.");
        die $self->error_message;
    }
    my $cmd = Genome::Model::Tools::Sam::ListReadGroups->create(input=>$bam_file, silence_output=>1);
    unless ($cmd->execute) {
        $self->error_message("Failed to run list read groups command for $bam_file");
        die $self->error_message;
    }

    my @read_groups = $cmd->read_groups;

    return map {{segment_type=>'read_group', segment_id=>$_}} @read_groups;
}

# Microarray stuff eventually need to subclass
sub genotype_microarray_raw_file {
    my $self = shift;

    my $disk_allocation = $self->disk_allocations;
    return if not $disk_allocation;

    my $absolute_path = $disk_allocation->absolute_path;
    Carp::confess('No absolute path for instrument data ('.$self->id.') disk allocation: '.$disk_allocation->id) if not $absolute_path;
    my $sample_name = $self->sample_name;
    Carp::confess('No sample name for instrument data: '.$self->id) if not $sample_name;

    # sanitize these 
    $sample_name =~ s/[^\w\-\.]/_/g;
    return $absolute_path.'/'.$sample_name.'.raw.genotype';
}

sub genotype_microarray_file_for_subject_and_version {
    my ($self, $subject_name, $version) = @_;

    Carp::confess('No reference name given to get genotype microarray file') if not $subject_name;
    Carp::confess('No version given to get genotype microarray file') if not defined $version;

    my $disk_allocation = $self->disk_allocations;
    return if not $disk_allocation;

    my $absolute_path = $disk_allocation->absolute_path;
    Carp::confess('No absolute path for instrument data ('.$self->id.') disk allocation: '.$disk_allocation->id) if not $absolute_path;
    my $sample_name = $self->sample_name;

    # sanitize these 
    $sample_name =~ s/[^\w\-\.]/_/g;
    $subject_name =~ s/[^\w\-\.]/_/g;
    Carp::confess('No sample name for instrument data: '.$self->id) if not $sample_name;

    return $absolute_path.'/'.$sample_name.'.'.$subject_name.'-'.$version.'.genotype';
}

sub genotype_microarray_file_for_human_version_37 {
    my $self = shift;
    return $self->genotype_microarray_file_for_subject_and_version('human', '37');
}

sub genotype_microarray_file_for_human_version_36 {
    my $self = shift;
    return $self->genotype_microarray_file_for_subject_and_version('human', '36');
}

sub genotype_microarray_file_for_reference_sequence_build {
    my ($self, $build) = @_;

    Carp::confess('No refernce sequence build given to get genotype microarray file') if not $build;

    return $self->genotype_microarray_file_for_subject_and_version($build->subject_name, $build->version);
}

1;

