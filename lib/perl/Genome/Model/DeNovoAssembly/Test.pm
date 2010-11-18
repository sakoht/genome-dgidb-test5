package Genome::Model::DeNovoAssembly::Test;

use strict;
use warnings;

require Carp;
use Data::Dumper 'Dumper';
require Genome::Model::Test;
require Genome::Utility::TestBase;

BEGIN {
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
}

sub processing_profile_params_for_assembler_and_platform {
    my ($self, %params) = @_;

    my $sequencing_platform = delete $params{sequencing_platform};
    Carp::confess "No sequencing platform given to create mock processing profile" unless $sequencing_platform;
    my $assembler_name = delete $params{assembler_name};
    Carp::confess "No assembler name given to create mock processing profile" unless $assembler_name;
    Carp::confess("Unknown params to get mock processing profile\n".Dumper(\%params)) if %params;

    #TODO make params trim specific too? eg, soap_solexa_bwa_trim
    my %assembler_sequencing_platform_params = (
        velvet_solexa =>  { 
            coverage => 0.5,#25000,
            assembler_version => '0.7.57-64',
            assembler_params => '-hash_sizes 31 33 35',
            read_processor => 'trimmer by-length -trim-length 10 | rename illumina-to-pcap',
	    post_assemble => 'standard-outputs',
        },
        soap_solexa => {
            assembler_version => '1.04',
            assembler_params => '-kmer_size 31 -resolve_repeats -kmer_frequency_cutoff 1',
            read_processor => 'trimmer bwa-style -trim-qual-level 10 | filter by-length --filter-length 35 | rename illumina-to-pcap',
	    post_assemble => 'standard-outputs',
        },
        newbler_454 => {
        },
    );

    my $specific_params = $assembler_sequencing_platform_params{ $assembler_name.'_'.$sequencing_platform };
    unless ( $specific_params ) {
        Carp::confess "Invalid assembler ($assembler_name) and sequencing platform ($sequencing_platform) combination";
    }

    $specific_params->{name} = 'De Novo Assembly ' . ucfirst $assembler_name . ' Test';
    $specific_params->{sequencing_platform} = $sequencing_platform;
    $specific_params->{assembler_name} = $assembler_name;
    
    return %$specific_params;
}

sub get_mock_processing_profile {
    my $self = shift;

    my %params = $self->processing_profile_params_for_assembler_and_platform(@_) or Carp::confess;
    my $pp = Genome::Model::Test->get_mock_processing_profile(
        class => 'Genome::ProcessingProfile::DeNovoAssembly',
        type_name => 'de novo assembly',
        %params,
    ) or Carp::confess "Can't get mock de novo assembly processing profile";
    
    Genome::Utility::TestBase->mock_methods(
        $pp,
        (qw/ 
            class_for_assembler
            assembler_params_as_hash
            _validate_assembler_and_params

            _validate_read_processor
            
            status_message
            /),
    );

    return $pp;
}

sub get_mock_subject {
    my $self = shift;

    my $sample_name = 'H_KT-185-1-0089515594';
    
    # 2851686380
    my $taxon = Genome::Utility::TestBase->create_mock_object(
        class => 'Genome::Taxon',
        domain => 'Bacteria',
        species_name => 'Escherichia coli 185-1',
        current_default_org_prefix => undef,
        estimated_genome_size => 4500000,,
        current_genome_refseq_id => undef,
        ncbi_taxon_id => undef,
        ncbi_taxon_species_name => undef,
        species_latin_name => 'Escherichia coli',
        strain_name => 185-1,
        subject_type => 'organism taxon',
    ) or Carp::confess "Can't create mock taxon";

    # 2851686381
    my $source = Genome::Utility::TestBase->create_mock_object(
        class => 'Genome::SampleSource',
        id => 2851686381,
        taxon_id => $taxon->id,
        name => $sample_name,
    ) or Carp::confess "Can't create mock source";

    # 2851686382
    my $subject = Genome::Utility::TestBase->create_mock_object(
        class => 'Genome::Sample',
        id => 2851686382,
        source_id => $source->id,
        source_type => 'organism individual',
        name => 'H_KT-185-1-0089515594',
        common_name => undef,
        extraction_label => '0089515594',
        extraction_type => 'genomic dna',
        extraction_desc => undef,
        cell_type => 'primary',
        tissue_desc => 'zv2_g_dna_posterior fornix',
        tissue_label => undef,
        organ_name => undef,
        taxon_id => $taxon->id,
    ) or Carp::confess "Can't create mock sample";

    return $subject;
}

sub get_mock_model {
    my $self = shift;

    # pp
    my $pp = $self->get_mock_processing_profile(@_) 
        or Carp::confess("Can't create mock de novo assembly pp");

    # subject
    my $subject = $self->get_mock_subject
        or Carp::confess("Can't get mock subject for de novo assembly model");

    # model
    my $model = Genome::Model::Test->get_mock_model(
        class => 'Genome::Model::DeNovoAssembly',
        processing_profile => $pp,
        subject => $subject,
    ) or Carp::confess "Can't get mock de novo assembly model";
    
    # methods
    Genome::Utility::TestBase->mock_methods(
        $model,
        (qw/ default_model_name _get_name_part_from_tissue_desc /),
    ) or die;

    # inst data
    my $sequencing_platform = $pp->sequencing_platform;
    my $inst_data_method = '_get_mock_'.$sequencing_platform.'_instrument_data';
    my $inst_data = $self->$inst_data_method
        or Carp::confess "Can't create mock instrument data for de novo assembly model";
    my $instrument_data_assignment = Genome::Utility::TestBase->create_mock_object(
        class => 'Genome::Model::InstrumentDataAssignment',
        model => $model,
        model_id => $model->id,
        instrument_data => $inst_data,
        instrument_data_id => $inst_data->id,
        first_build_id => undef,
    ) or Carp::confess("Can't assign instrument data to de novo assembly model");

    return $model;
}

sub get_mock_build {
    my ($self, %params) = @_;

    my $model = delete $params{model};
    Carp::confess "No de novo model given to create mock build" unless $model;
    my $use_example_directory = delete $params{use_example_directory};
    Carp::confess("Unknown params to get mock build:\n".Dumper(\%params)) if %params;
    
    my $build = Genome::Model::Test->get_mock_build(
        class => 'Genome::Model::Build::DeNovoAssembly::'.Genome::Utility::Text::string_to_camel_case($model->assembler_name),
        model => $model,
        data_directory => ( 
            $use_example_directory
            ? $self->example_directory_for_model($model)
            : undef 
        ),
    )
        or Carp::confess("Can't add mock build to model");

    $build->mock('instrument_data', sub{ return $model->instrument_data; });

    my @build_methods_to_mock = (qw/
        status_message description

        interesting_metric_names
        calculate_metrics
        set_metrics
        calculate_reads_attempted
        calculate_average_insert_size

        genome_size
        calculate_base_limit_from_coverage
        processed_reads_count

        edit_dir
        gap_file
        contigs_bases_file
        contigs_fasta_file
        contigs_quals_file
        read_info_file
        reads_placed_file
        supercontigs_agp_file
        supercontigs_fasta_file
        stats_file

        read_processor_output_files_for_instrument_data
        existing_assembler_input_files

        center_name

    /);
    my %build_specific_methods_to_mock = (
        newbler => [qw//],
        soap => [qw/
            file_prefix
            assembler_forward_input_file_for_library_id
            assembler_reverse_input_file_for_library_id
            assembler_fragment_input_file_for_library_id
            libraries_with_existing_assembler_input_files
            existing_assembler_input_files_for_library_id

            soap_config_file
            soap_output_dir_and_file_prefix
            soap_scaffold_sequence_file 
            soap_output_file_for_ext

            pga_agp_file
            pga_contigs_fasta_file
            pga_scaffolds_fasta_file

        /],
        velvet => [qw/
            collated_fastq_file
            assembly_afg_file
            sequences_file
            velvet_ace_file
            contigs_fasta_file
            assembly_afg_file
            contigs_fasta_file
            sequences_file
            ace_file
        /],
    );
    Genome::Utility::TestBase->mock_methods(
        $build,
        @build_methods_to_mock,
        @{$build_specific_methods_to_mock{$build->processing_profile->assembler_name}},
    ) or die;

    Genome::Utility::TestBase->mock_methods(
        $build,
        map { join('_', split(m#\s#)) } $build->interesting_metric_names,
    ) or die;

    return $build;
}

#< Example Dirs >#
sub base_directory {
    return '/gsc/var/cache/testsuite/data/Genome-Model/DeNovoAssembly';
}

my %dirs_versions = (
    soap_solexa => '8',
    velvet_solexa => '0.2',
    newbler_454 => '0.1',
);

sub example_directory_for_model {
    my ($self, $model) = @_;

    Carp::confess "No model to get example directory" unless $model;
    
    my $assembler_platform = $model->assembler_name.'_'.$model->sequencing_platform;
    my $dir = $self->base_directory.'/'.$assembler_platform.'_build_v'.$dirs_versions{$assembler_platform};

    Carp::confess("Example directory ($dir) for de novo assembly model does not exist.") unless -d $dir;
    
    return $dir;
}

sub output_prefix_name {
    my ($self, $model) = @_;

    return $model->subject_name.'_WUGC';
}
#<>#

#< Instrument Data >#
sub _instrument_data_dir {
    return $_[0]->base_directory.'/inst_data/';
}

sub _get_mock_solexa_instrument_data {
    my $self = shift;

    my $id = 2854709902;
    my $inst_data = Genome::Utility::TestBase->create_mock_object(
        class => 'Genome::InstrumentData::Solexa',
        id => $id,
        seq_id => $id,
        sequencing_platform => 'solexa',
        flow_cell_id => '61H93',
        lane => 8,
        read_length => 100,
        archive_path => $self->_instrument_data_dir.'/'.$id.'/sequence_61H93_8_CGATGT.tar.gz',
        index_sequence => 'CGATGT',
        subset_name => '8-CGATGT',
        is_external => 0,
        is_paired_end => 1,
        library_id => '2852968107',
        library_name => 'H_KT-185-1-0089515594-lib1',
        sample_name => 'H_KT-185-1-0089515594',
        clusters => 17500,
        fwd_clusters => 17500,
        rev_clusters => 17500,
        median_insert_size => 260,# 181, but 260 was used to generate assembly
        sd_above_insert_size => 62,
        sd_below_insert_size => 38,
    ) or Carp::confess "Can't create mock solexa instrument data";
    $inst_data->set_always('sra_sample_id', 'SRS000001');

    return $inst_data;
}

sub _get_mock_454_instrument_data {
    # FIXME!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    my $self = shift;

    my $id = 222;
    my $full_path = $self->_instrument_data_dir('454').'/'.$id;
    #Carp::confess "Mock instrument data directory ($full_path) does not exist" unless -d $full_path;
    my $inst_data = Genome::Utility::TestBase->create_mock_object(
        class => 'Genome::InstrumentData::454',
        id => $id,
        seq_id => $id,
        region_id => $id,
        analysis_name => 'D_2010_01_10_04_22_16_blade9-2-5_fullProcessing',
        region_number => 2,
        total_reads => 20,
        total_raw_wells => 1176187,
        total_key_pass => 1169840,
        incoming_dna_name => 'Pooled_Library-2009-12-31_1-1',
        copies_per_bead => 2.5,
        run_name => 'R_2010_01_09_11_08_12_FLX08080418_Administrator_100737113',
        key_pass_wells => 1170328,
        predicted_recovery_beads => 371174080,
        fc_id => undef,
        sample_set => 'Tarr NEC 16S Metagenomic Sequencing master set',
        research_project => 'Tarr NEC 16S Metagenomic Sequencing',
        paired_end => 0,
        sample_name => 'H_MA-.0036.01-89503877',
        library_name => 'Pooled_Library-2009-12-31_1',
        beads_loaded => 1999596,
        ss_id => undef,
        supernatant_beads => 254520,
        sample_id => 2847037746,
        library_id => 2848636935,
        #library_name => 'Pooled_DNA-2009-03-09_23-lib1',
        sequencing_platform => '454',
        full_path => $full_path,
    ) or Carp::confess "Unable to create mock 454 id #";
    $inst_data->mock('fasta_file', sub { 
            return $full_path.'/zymo4_pool7_DNA_extract.fasta';
        }
    );
    $inst_data->mock('dump_to_file_system', sub{ return 1; });

    return $inst_data;
}
#<>#

1;

=pod

=head1 Tests

=head1 Disclaimer

 Copyright (C) 2010 Washington University Genome Sequencing Center

 This script is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY
 or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
 License for more details.

=head1 Author(s)

 Eddie Belter <ebelter@genome.wustl.edu>

=cut

#$HeadURL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/Genome/MetagenomicComposition16s/Test.pm $
#$Id: Test.pm 54265 2010-01-05 16:50:07Z ebelter $

