#!/usr/bin/env perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use strict;
use warnings;

use above 'Genome';

require File::Compare;
use Test::More;

my $machine_hardware = `uname -m`;
like($machine_hardware, qr/x86_64/, 'on 64 bit machine') or die;

use_ok('Genome::Model::Build::DeNovoAssembly::Velvet') or die;

my $base_dir = '/gsc/var/cache/testsuite/data/Genome-Model/DeNovoAssembly';
my $archive_path = $base_dir.'/inst_data/-7777/archive.tgz';
ok(-s $archive_path, 'inst data archive path') or die;
my $example_version = '4';
my $example_dir = $base_dir.'/velvet_solexa_build_v'.$example_version;
ok(-d $example_dir, 'example dir') or die;
my $tmpdir = File::Temp::tempdir(CLEANUP => 1);

my $taxon = Genome::Taxon->create(
    name => 'Escherichia coli TEST',
    domain => 'Bacteria',
    current_default_org_prefix => undef,
    estimated_genome_size => 4500000,
    current_genome_refseq_id => undef,
        ncbi_taxon_id => undef,
        ncbi_taxon_species_name => undef,
    species_latin_name => 'Escherichia coli',
    strain_name => 'TEST',
);
ok($taxon, 'taxon') or die;
my $sample = Genome::Sample->create(
    id => -1234,
    name => 'TEST-000',
    taxon_id => $taxon->id,
);
ok($sample, 'sample') or die;
my $library = Genome::Library->create(
    id => -12345,
    name => $sample->name.'-testlibs',
    sample_id => $sample->id,
);
ok($library, 'library') or die;

my $instrument_data = Genome::InstrumentData::Solexa->create(
    id => -7777,
    sequencing_platform => 'solexa',
    read_length => 100,
    subset_name => '8-CGATGT',
    run_type => 'Paired',
    library => $library,
    median_insert_size => 260,# 181, but 260 was used to generate assembly
    archive_path => $archive_path,
    fwd_clusters => 15000,
    rev_clusters => 15000,
);
ok($instrument_data, 'instrument data');
ok($instrument_data->is_paired_end, 'inst data is paired');
ok(-s $instrument_data->archive_path, 'inst data archive path');

my $pp = Genome::ProcessingProfile::DeNovoAssembly->create(
    name => 'De Novo Assembly Velvet Test',
    sequencing_platform => 'solexa',
    coverage => 0.5,#25000,
    assembler_name => 'velvet one-button',
    assembler_version => '0.7.57-64',
    assembler_params => '-hash_sizes 31 33 35 -min_contig_length 100',
    read_processor => 'trimmer by-length -trim-length 10 | rename illumina-to-pcap',
    post_assemble => 'standard-outputs',
);
ok($pp, 'pp') or die;

my $model = Genome::Model::DeNovoAssembly->create(
    processing_profile => $pp,
    subject_name => $taxon->name,
    subject_type => 'species_name',
    center_name => 'WUGC',
);
ok($model, 'soap de novo model') or die;
ok($model->add_instrument_data($instrument_data), 'add inst data to model');

my $build = Genome::Model::Build::DeNovoAssembly->create(
    model => $model,
    data_directory => $tmpdir,
);
ok($build, 'created build');
my $example_build = Genome::Model::Build->create(
    model => $model,
    data_directory => $example_dir,
);
ok($example_build, 'create example build');

# PREPARE INST DATA
my @existing_assembler_input_files = $build->existing_assembler_input_files;
ok(!@existing_assembler_input_files, 'assembler input files do not exist');

my $prepare = Genome::Model::Event::Build::DeNovoAssembly::PrepareInstrumentData->create(build => $build, model => $model);
ok($prepare, 'create prepare instrument data');
$prepare->dump_status_messages(1);
ok($prepare->execute, 'execute prepare instrument data');

@existing_assembler_input_files = $build->existing_assembler_input_files;
is(@existing_assembler_input_files, 1, 'assembler input files exist');
my @example_existing_assembler_input_files = $example_build->existing_assembler_input_files;
is(@existing_assembler_input_files, 1, 'example assembler input files do not exist');
is(
    File::Compare::compare($existing_assembler_input_files[0], $example_existing_assembler_input_files[0]),
    0, 
    'assembler input file matches',
);

# ASSEMBLE
my %assembler_params = $model->processing_profile->velvet_one_button_params($build);
#print Data::Dumper::Dumper(\%assembler_params);
is_deeply(
    \%assembler_params,
    {
        'version' => '0.7.57-64',
        'min_contig_length' => '100',
        'file' => $existing_assembler_input_files[0],
        'ins_length' => '260',
        'hash_sizes' => [
        '31',
        '33',
        '35'
        ],
        'output_dir' => $build->data_directory,
        'genome_len' => '4500000'
    },
    'assembler params',
);

my $assemble = Genome::Model::Event::Build::DeNovoAssembly::Assemble->create(build => $build, model => $model);
ok($assemble, 'create assemble');
$assemble->dump_status_messages(1);
ok($assemble->execute, 'execute assemble');

for my $file_name (qw/ contigs_fasta_file sequences_file assembly_afg_file /) {
    my $file = $build->$file_name;
    ok(-s $file, "Build $file_name exists");
    my $example_file = $example_build->$file_name;
    ok(-s $example_file, "Example $file_name exists");
    is( File::Compare::compare($file, $example_file), 0, "Generated $file_name matches example file");
}


# TODO metrics

#print $build->data_directory."\n"; <STDIN>;
done_testing();
exit;

