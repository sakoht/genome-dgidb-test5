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

if (Genome::Config->arch_os ne 'x86_64') {
    plan skip_all => 'requires 64-bit machine';
}

use_ok('Genome::Model::Build::DeNovoAssembly::Newbler') or die;

my $base_dir = '/gsc/var/cache/testsuite/data/Genome-Model/DeNovoAssembly';
my $archive_path = $base_dir.'/inst_data/-7777/archive.tgz';
ok(-s $archive_path, 'inst data archive path') or die;
my $example_dir = $base_dir.'/newbler_v5';
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
    fragment_size_range => 260,
);
ok($library, 'library') or die;

my $instrument_data = Genome::InstrumentData::Solexa->create(
    id => -7777,
    sequencing_platform => 'solexa',
    read_length => 100,
    subset_name => '8-CGATGT',
    index_sequence => 'CGATGT',
    run_name => 'XXXXXX/8-CGATGT',
    run_type => 'Paired',
    flow_cell_id => 'XXXXXX',
    lane => 8,
    library => $library,
    archive_path => $archive_path,
    median_insert_size => 260,
    clusters => 15000,
    fwd_clusters => 15000,
    rev_clusters => 15000,
    analysis_software_version => 'not_old_iilumina',
);
ok($instrument_data, 'instrument data');
ok($instrument_data->is_paired_end, 'inst data is paired');
ok(-s $instrument_data->archive_path, 'inst data archive path');

my $pp = Genome::ProcessingProfile::DeNovoAssembly->create(
    name => 'De Novo Assembly Newbler Test',
    assembler_name => 'newbler de-novo-assemble',
    assembler_version => 'mapasm454_source_03152011',
    assembler_params => '-consed -rip',
    post_assemble => 'standard-outputs --min_contig_length 50',
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
is($build->reads_attempted, 30000, 'reads attempted');
is($build->reads_processed, 30000, 'reads processed');
is($build->reads_processed_success, '1.000', 'reads processed success');

@existing_assembler_input_files = $build->existing_assembler_input_files;
is(@existing_assembler_input_files, 1, 'assembler input files exist');

my @example_existing_assembler_input_files = $example_build->existing_assembler_input_files;
is(@example_existing_assembler_input_files, 1, 'example assembler input files exist');
is(
    File::Compare::compare($existing_assembler_input_files[0], $example_existing_assembler_input_files[0]),
    0, 
    'assembler input file matches',
);

# ASSEMBLE
my $assembler_rusage = $build->assembler_rusage;
#is($assembler_rusage, "", 'assembler rusage');
my %assembler_params = $build->assembler_params;
print Data::Dumper::Dumper(\%assembler_params);
is_deeply(
    \%assembler_params,
    {
        'version' => 'mapasm454_source_03152011',
        'input_files' => [ $build->data_directory.'/-7777-input.fastq' ],
        'rip' => 1,
        'consed' => 1,
        'output_directory' => $build->data_directory,
    },
    'assembler params',
);

my $assemble = Genome::Model::Event::Build::DeNovoAssembly::Assemble->create(build => $build, model => $model);
ok($assemble, 'create assemble');
$assemble->dump_status_messages(1);
ok($assemble->execute, 'execute assemble');
# check build output files
for my $file_name (qw/ all_contigs_fasta_file all_contigs_qual_file all_contigs_ace_file / ) {
    my $file = $build->$file_name;
    ok(-s $file, "Build $file_name exists");
    my $example_file = $example_build->$file_name;
    ok(-s $example_file, "Example $file_name exists");
    is(File::Compare::compare($file, $example_file), 0, "Generated $file_name matches example file");
}

#POST ASSEMBLE
my $post_assemble = Genome::Model::Event::Build::DeNovoAssembly::PostAssemble->create( build => $build, model => $model );
ok( $post_assemble, 'Created post assemble newbler' );
ok( $post_assemble->execute, 'Executed post assemble newble' );
#check post asm output files
foreach my $file_name (qw/
    454Contigs.ace.1 Pcap.454Contigs.ace
    gap.txt contigs.quals contigs.bases
    reads.placed readinfo.txt
    reads.unplaced reads.unplaced.fasta
    supercontigs.fasta supercontigs.agp
    /) {
    my $example_file = $example_dir.'/consed/edit_dir/'.$file_name;
    ok(-e $example_file, "$file_name example file exists");
    my $file = $build->data_directory.'/consed/edit_dir/'.$file_name;
    ok(-e $file, "$file_name file exists");
    is(File::Compare::compare($file, $example_file), 0, "$file_name files match");
}

# Report and Metrics
my $report = Genome::Model::Event::Build::DeNovoAssembly::Report->create( build => $build, model => $model );
ok( $report, 'Created report' );
$report->dump_status_messages(1);
ok( $report->execute, 'Executed report' );
ok( -s $example_build->stats_file, 'Example build stats file exists' );
ok( -s $build->stats_file, 'Test created stats file' );
is(File::Compare::compare($example_build->stats_file,$build->stats_file), 0, 'Stats files match' );
print 'gvimdiff '.$example_build->stats_file.' '.$build->stats_file."\n";
my %expected_metrics = (
    'assembly_length' => 65818,
    'contigs_average_length' => 210,
    'contigs_count' => 314,
    'contigs_lengths' => 65818,
    'contigs_major_average_length' => 603,
    'contigs_major_count' => 4,
    'contigs_major_length' => 2411,
    'contigs_major_n50_count' => 2,
    'contigs_major_n50_length' => 591,
    'contigs_n50_count' => 125,
    'contigs_n50_length' => 208,
    'genome_size' => '4500000',
    'insert_size' => '260',
    'major_contig_threshold' => '500',
    'reads attempted' => 30000,
    'reads processed success' => '1.000',
    'reads processed' => 30000,
    'reads_assembled' => '1813',
    'reads_assembled_duplicate' => 0,
    'reads_assembled_success' => '0.060',
    'reads_attempted' => 30000,
    'reads_processed' => 30000,
    'reads_processed_success' => '1.000',
    'supercontigs_average_length' => 210,
    'supercontigs_count' => 314,
    'supercontigs_length' => 65818,
    'supercontigs_major_average_length' => 603,
    'supercontigs_major_count' => 4,
    'supercontigs_major_length' => 2411,
    'supercontigs_major_n50_count' => 2,
    'supercontigs_major_n50_length' => 591,
    'supercontigs_n50_count' => 125,
    'supercontigs_n50_length' => 208,
    'contigs_length' => 65818,
);
my %build_metrics = map { $_->name => $_->value } $build->metrics;
#print Data::Dumper::Dumper(\%build_metrics);
for my $metric_name ( $build->metric_names ) {
    is($build_metrics{$metric_name}, $expected_metrics{$metric_name}, "$metric_name matches" );
}

#print $build->data_directory."\n"; <STDIN>;
done_testing();
exit;

