package Genome::InstrumentData::454;

use strict;
use warnings;

use Genome;

require Carp;

class Genome::InstrumentData::454 {
    is  => 'Genome::InstrumentData',
    table_name => <<'EOS'
        (
            select 
                to_char(case when ri.index_sequence is null then ri.region_id else ri.seq_id end) id,
                '454' sequencing_platform,
                r.region_id genome_model_run_id, --legacy
                BEADS_LOADED,
                COPIES_PER_BEAD,          
                FC_ID,                    
                INCOMING_DNA_NAME,        
                KEY_PASS_WELLS,           
                ri.library_id, --r.LIBRARY_ID,               
                lib.full_name library_name, -- r.LIBRARY_NAME,             
                PAIRED_END,               
                PREDICTED_RECOVERY_BEADS, 
                r.REGION_ID,                
                REGION_NUMBER,            
                RESEARCH_PROJECT,         
                RUN_NAME,                 
                lib.SAMPLE_ID,                
                s.full_name SAMPLE_NAME,              
                SAMPLE_SET,               
                SS_ID,                    
                SUPERNATANT_BEADS,        
                TOTAL_KEY_PASS,           
                TOTAL_RAW_WELLS,
                NUM_BASES,
                NUM_READS,
                INDEX_SEQUENCE
            from GSC.run_region_454 r 
            join GSC.region_index_454 ri on ri.region_id = r.region_id
            join GSC.library_summary lib on lib.library_id = ri.library_id
            join GSC.organism_sample s on s.organism_sample_id = lib.sample_id
        ) x454_detail
EOS
    ,
    has_constant => [
        sequencing_platform => { value => '454' },
    ],    
    has_optional => [
        _fasta_file => {
                        is => 'String',
                        is_transient => 1,
                        is_mutable => 1,
                  },
        _qual_file => {
                       is => 'String',
                       is_transient => 1,
                       is_mutable => 1,
                   },
        #< Run Region 454 from DW Attrs >#
        run_region_454     => {
            doc => '454 Run Region from LIMS.',
            is => 'GSC::RunRegion454',
            calculate => q| GSC::RunRegion454->get($region_id); |,
            calculate_from => ['region_id']
        },
        region_index_454     => {
            doc => 'Region Index 454 from LIMS.',
            is => 'GSC::RegionIndex454',
            calculate => q| GSC::RegionIndex454->get($id); |,
            calculate_from => ['id']
        },
        region_id           => { },
        region_number       => { },
        total_reads         => { column_name => "NUM_READS" },
        total_bases_read    => { column_name => "NUM_BASES" },
        is_paired_end       => { column_name => "PAIRED_END" },
        index_sequence      => { },

        # stolen from Genome::InstrumentData::Solexa
  
        # basic relationship to the "source" of the lane
        library         => { is => 'Genome::Library', id_by => ['library_id'] },
        library_id      => { is => 'Number', },

        # these are indirect via library, but must be set directly for lanes missing library info
        sample              => { is => 'Genome::Sample', id_by => ['sample_id'] },
        sample_id           => { is => 'Number', },

        sample_source       => { is => 'Genome::SampleSource', via => 'sample', to => 'source' },
        sample_source_name  => { via => 'sample_source', to => 'name' },

        # indirect via the sample source, but we let the sample manage that
        # since we sometimes don't know the source, it also tracks taxon directly
        taxon               => { via => 'sample', to => 'taxon', is => 'Genome::Taxon' },
        species_name        => { via => 'taxon' },
        target_set         => {
            is => 'Genome::Capture::Set',
            calculate_from => 'target_region_set_name',
            calculate => q|Genome::Capture::Set->get(name => $target_region_set_name)|,
        },
    ],
};

sub _default_full_path {
    my $self = shift;
    return sprintf('%s/%s/%s', $self->_data_base_path, $self->run_name, $self->region_id);
}

sub calculate_alignment_estimated_kb_usage {
    my $self = shift;
    return 500000;
}

sub is_external {
    return;
}

sub dump_sanger_fastq_files {
    my $self = shift;
    
    my %params = @_;
    
    unless (-s $self->sff_file) {
        $self->error_message(sprintf("SFF file (%s) doesn't exist for 454 instrument data %s", $self->sff_file, $self->id));
        die $self->error_message;
    }
    
    my $dump_directory = delete $params{'directory'} || Genome::Utility::FileSystem->base_temp_directory();
    
    my $output_file = sprintf("%s/%s-output.fastq", $dump_directory, $self->id);
    
    my $cmd = Genome::Model::Tools::454::Sff2Fastq->create(sff_file => $self->sff_file,
                                                           fastq_file => $output_file);
    
    unless ($cmd->execute) {
        $self->error_message("Sff2Fastq failed while dumping fastq file for instrument data " . $self->id);
        die $self->error_message;
    }
    
    unless (-s $output_file) {
        $self->error_message("Sff2Fastq claims it worked, but the output file was gone or empty length while dumping fastq file for instrument data "
                             . $self->id . " expected output file was $output_file");
        die $self->error_message;
    }
    
    return ($output_file);
}

sub dump_fasta_file {
    my ($self, %params) = @_;
    $params{type} = 'fasta';
    return $self->_run_sffinfo(%params);
}

sub dump_qual_file {
    my ($self, %params) = @_;
    $params{type} = 'qual';
    return $self->_run_sffinfo(%params);
}

sub _run_sffinfo {
    my ($self, %params) = @_;

    # Type 
    my $type = delete $params{type};
    my %types_params = (
        fasta => '-s',
        qual => '-q',
    );
    unless ( defined $type and grep { $type eq $_ } keys %types_params ) { # should not happen
        Carp::confess("No or invalid type (".($type || '').") to run sff info.");
    }

    # Verify 64 bit
    unless ( Genome::Config->arch_os =~ /x86_64/ ) {
        Carp::confess(
            $self->error_message('Dumping $type file must be run on 64 bit machine.')
        );
    }
    
    # SFF
    my $sff_file = $self->sff_file;
    unless ( -s $sff_file ) {
        Carp::confess(
            $self->error_message(
                "SFF file ($sff_file) doesn't exist for 454 instrument data (".$self->id.")"
            )
        );
    }

    # File
    my $directory = delete $params{'directory'} 
        || Genome::Utility::FileSystem->base_temp_directory();
    my $file = sprintf("%s/%s.%s", $directory, $self->id, $type);
    unlink $file if -e $file;
    
    # SFF Info
    my $sffinfo = Genome::Model::Tools::454::Sffinfo->create(
        sff_file => $sff_file,
        output_file => $file,
        params => $types_params{$type},
    );
    unless ( $sffinfo ) {
        Carp::confess(
            $self->error_message("Can't create SFF Info command.")
        );
    }
    unless ( $sffinfo->execute ) {
        Carp::confess(
            $self->error_message("SFF Info command failed to dump $type file for instrument data (".$self->id.")")
        );
    }

    # Verify
    unless ( -s $file ) {
        Carp::confess(
            $self->error_message("SFF info executed, but a fasta was not produced for instrument data (".$self->id.")")
        );
    }

    return $file;
}

sub resolve_fasta_path {
    my $self = shift;
    my $full_path = $self->full_path;
    unless ($full_path) {
        $full_path = $self->resolve_full_path;
    }
    unless (Genome::Utility::FileSystem->create_directory($full_path)) {
        $self->error_message("Failed to create instrument data directory '$full_path'");
        return;
    }
    return $full_path .'/'. $self->subset_name .'.fa';
}

sub resolve_qual_path {
    my $self = shift;
    my $full_path = $self->full_path;
    unless ($full_path) {
        $full_path = $self->resolve_full_path;
    }
    unless (Genome::Utility::FileSystem->create_directory($full_path)) {
        $self->error_message("Failed to create instrument data directory '$full_path'");
        return;
    }
    return $full_path .'/'. $self->subset_name .'.qual';
}

sub qual_file {
    my $self = shift;

    unless ($self->_qual_file) {
        $self->_qual_file($self->resolve_qual_path);
    }
    unless (-s $self->_qual_file) {
        unless (-e $self->sff_file) {
            $self->error_message('Failed to find sff_file: '. $self->sff_file);
            die($self->error_message);
        }
        #FIXME ALLOCATE 
        unless (Genome::Model::Tools::454::Sffinfo->execute(
                                                            sff_file => $self->sff_file,
                                                            output_file => $self->_qual_file,
                                                            params => '-q',
                                                        )) {
            $self->error_message('Failed to convert sff to qual file');
            die($self->error_message);
        }
    }
    return $self->_qual_file;
}

sub fasta_file {
    my $self = shift;

    unless ($self->_fasta_file) {
        $self->_fasta_file($self->resolve_fasta_path);
    }
    unless (-s $self->_fasta_file) {
        unless (-e $self->sff_file) {
            $self->error_message('Failed to find sff_file: '. $self->sff_file);
            die($self->error_message);
        }
        #FIXME ALLOCATE 
        unless (Genome::Model::Tools::454::Sffinfo->execute(
                                                            sff_file => $self->sff_file,
                                                            output_file => $self->_fasta_file,
                                                            params => '-s',
                                                        )) {
            $self->error_message('Failed to convert sff to fasta file');
            die($self->error_message);
        }
    }
    return $self->_fasta_file;
}

#FIXME MOVE TO BUILD 
sub trimmed_sff_file {
    my $self = shift;
    my $full_path = $self->resolve_full_path;
    unless (-d $full_path) {
        Genome::Utility::FileSystem->create_directory($full_path);
    }
    return $full_path .'/'. $self->sff_basename .'_trimmed.sff';
}

#< SFF >#
sub sff_file {
    # FIXME this was updated, but legacy code automatically dumped the region
    #  sff if it didn't exist
    my $self = shift;

    # Use the region index first.
    my $region_index_454 = $self->region_index_454;
    # If the region index has an index sequence, it's indexed. Use its sff file
    if ( $region_index_454 and $region_index_454->index_sequence ) {
        my $sff_file_object = $region_index_454->get_index_sff;
        return unless $sff_file_object;
        return $sff_file_object->stringify;
        # get_index_sff does 2 checks:
        #  is there an index sequence?  we know this is true here
        #  are there reads?
        #  If there aren't any reads, this method reurns undef, and that is ok.
        #  If there are reads, the sff file should exist. If it doesn't, it dies
    }

    # If no index sequence, this is the 'parent' region
    my $sff_file;
    eval {
        $sff_file = $self->run_region_454->sff_filesystem_location_string;
    };

    # It this is defined, the file should exist
    return $sff_file if defined $sff_file;

    # If not defined, the sff does not exist, dump it and 
    #  return file name on apipe disk
    $sff_file = sprintf('%s/%s.sff', $self->resolve_full_path, $self->id);
    return $sff_file if -e $sff_file;

    #FIXME ALLOCATE 
    unless ( $self->create_data_directory_and_link ) {
        $self->error_message('Failed to create directory and link');
        return;
    }
    my $lock = Genome::Utility::FileSystem->lock_resource(
        lock_directory => $self->resolve_full_path,
        resource_id => $self->id,
        max_try => 60,
    );
    unless ( $lock ) {
        $self->error_message('Failed to lock_resource '. $self->id);
        return;
    }
    unless ( $self->run_region_454->dump_sff(filename => $sff_file) ) {
        $self->error_message('Failed to dump sff file to '. $sff_file);
        return;
    }
    my $unlock = Genome::Utility::FileSystem->unlock_resource(
        lock_directory => $self->resolve_full_path,
        resource_id => $self->id,
    );
    unless ( $unlock ) {
        $self->error_message('Failed to unlock_resource '. $self->id);
        return;
    }
    return $sff_file;
}

sub sff_basename {
    my $self = shift;
    return File::Basename::basename($self->sff_file,'.sff');
}
#<>#

sub amplicon_header_file {
    my $self = shift;
    my $amplicon_header_file = $self->full_path .'/amplicon_headers.txt';
    unless (-e $amplicon_header_file) {
        my $fh = $self->create_file('amplicon_header_file',$amplicon_header_file);
        $fh->close;
        unlink($amplicon_header_file);
        my $amplicon = Genome::Model::Command::Report::Amplicons->create(
                                                                         sample_name => $self->sample_name,
                                                                         output_file => $amplicon_header_file,
                                                                     );
        unless ($amplicon) {
            $self->error_message('Failed to create amplicon report tool');
            return;
        }
        unless ($amplicon->execute) {
            $self->error_message('Failed to execute command '. $amplicon->command_name);
            return;
        }
    }
    return $amplicon_header_file;
}

sub run_identifier {
    my $self = shift;

    my $ar_454 = $self->run_region_454->get_analysis_run_454;

    my $pse = GSC::PSE->get($ar_454->pse_id);
    my $loadpse = $pse->get_load_pse;
    my $barcode = $loadpse->picotiter_plate;
    
    return $barcode->barcode->barcode;
}

sub run_start_date_formatted {
    my $self = shift;

    my ($y, $m, $d) = $self->run_name =~ m/R_(\d{4})_(\d{2})_(\d{2})/;

    my $dt_format = UR::Time->config('datetime');
    UR::Time->config(datetime=>'%Y-%m-%d');
    my $dt = UR::Time->numbers_to_datetime(0, 0, 0, $d, $m, $y);
    UR::Time->config(datetime=>$dt_format);

    return $dt; 
}

1;

#$HeadURL$
#$Id$
