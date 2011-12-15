#!/usr/bin/env perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use strict;
use warnings;

use above 'Genome';

require File::Compare;
use File::Temp;
use Test::More;

if (Genome::Config->arch_os ne 'x86_64') {
    plan skip_all => 'requires 64-bit machine';
}

use_ok('Genome::Model::Build::DeNovoAssembly::Soap') or die;

my $base_dir = '/gsc/var/cache/testsuite/data/Genome-Model/DeNovoAssembly';
my $archive_path = $base_dir.'/inst_data/-7777/archive.tgz';
ok(-s $archive_path, 'inst data archive path') or die;
my $example_dir = $base_dir.'/soap_v10';
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
    clusters => 15000,
    fwd_clusters => 15000,
    rev_clusters => 15000,
    analysis_software_version => 'not_old_iilumina',
);
ok($instrument_data, 'instrument data');
ok($instrument_data->is_paired_end, 'inst data is paired');
ok(-s $instrument_data->archive_path, 'inst data archive path');

my $pp = Genome::ProcessingProfile::DeNovoAssembly->create(
    name => 'De Novo Assembly Soap Test',
    assembler_name => 'soap de-novo-assemble',
    assembler_version => '1.04',
    assembler_params => '-kmer_size 31 -resolve_repeats -kmer_frequency_cutoff 1',
    read_processor => 'trim bwa-style -trim-qual-level 10 | filter by-length -filter-length 35 | rename illumina-to-pcap',
    post_assemble => 'standard-outputs -min_contig_length 10',
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
my @invalid_tags = $build->validate_for_start;
print Data::Dumper::Dumper(@invalid_tags);
ok(!@invalid_tags, 'build can start');
my $example_build = Genome::Model::Build->create(
    model => $model,
    data_directory => $example_dir,
);
ok($example_build, 'create example build');

my $file_prefix = $build->file_prefix;
is($file_prefix, Genome::Utility::Text::sanitize_string_for_filesystem($model->subject_name).'_WUGC', 'file prefix');
my $library_file_base = $build->data_directory.'/'.$file_prefix;

# PREPARE INST DATA
my $prepare = Genome::Model::Event::Build::DeNovoAssembly::PrepareInstrumentData->create(build => $build, model => $model);
ok($prepare, 'create prepare instrument data');
$prepare->dump_status_messages(1);
ok($prepare->execute, 'execute prepare instrument data');

my ($inst_data) = $build->instrument_data;
ok($inst_data, 'instrument data for build');
my $library_id = $inst_data->library_id;
ok($library_id, 'library id for inst data');
my $assembler_fwd_input_file_for_library_id = $build->assembler_forward_input_file_for_library_id($library_id);
is($assembler_fwd_input_file_for_library_id, $library_file_base.'.'.$library_id.'.forward.fastq', 'forward fastq file for library id');
is(
    File::Compare::compare($assembler_fwd_input_file_for_library_id, $example_build->assembler_forward_input_file_for_library_id($library_id)),
    0, 
    'assembler fwd input file matches',
);
my $assembler_rev_input_file_for_library_id = $build->assembler_reverse_input_file_for_library_id($library_id);
is($assembler_rev_input_file_for_library_id, $library_file_base.'.'.$library_id.'.reverse.fastq', 'reverse fastq file for library id');
is(
    File::Compare::compare($assembler_rev_input_file_for_library_id, $example_build->assembler_reverse_input_file_for_library_id($library_id)),
    0, 
    'assembler rev input file matches',
);
my $assembler_fragment_input_file_for_library_id = $build->assembler_fragment_input_file_for_library_id($library_id);
is($assembler_fragment_input_file_for_library_id, $library_file_base.'.'.$library_id.'.fragment.fastq', 'fragment fastq file for library id');
my @libraries = $build->libraries_with_existing_assembler_input_files;
is_deeply( # also tests existing_assembler_input_files_for_library_id
    \@libraries,
    [
        {
            library_id => -12345,
            insert_size => 260,
            paired_fastq_files => [ 
                $assembler_fwd_input_file_for_library_id, $assembler_rev_input_file_for_library_id 
            ],
        },
    ],
    'libraries and existing assembler input files',
);
my @existing_assembler_input_files = $build->existing_assembler_input_files;
is_deeply(
    \@existing_assembler_input_files,
    $libraries[0]->{paired_fastq_files},
    'existing assembler input files',
);

# ASSEMBLE - IMPORT RUSAGE/PARAMS
my $assembler_name = $pp->assembler_name;
$pp->assembler_name('soap import');
my $assembler_rusage = $build->assembler_rusage;
is($assembler_rusage, "-R 'select[type==LINUX64] rusage[internet_download_mbps=100] span[hosts=1]'", 'assembler rusage');
my %assembler_params = $build->assembler_params;
is($assembler_params{import_location}, '/WholeMetagenomic/03-Assembly/PGA/Escherichia coli TEST_WUGC', 'import location');
$pp->assembler_name($assembler_name); # reset

# ASSEMBLE
$assembler_rusage = $build->assembler_rusage;
my $queue = ( $build->run_by eq 'apipe-tester' ) ? 'alignment-pd' : 'apipe';
is($assembler_rusage, "-q $queue -n 4 -R 'span[hosts=1] select[type==LINUX64 && mem>30000] rusage[mem=30000]' -M 30000000", 'assembler rusage');
%assembler_params = $build->assembler_params;
#print Data::Dumper::Dumper(\%assembler_params);
is_deeply(
    \%assembler_params,
    {
        'version' => '1.04',
        'resolve_repeats' => 1,
        'config_file' => $build->data_directory.'/config_file',
        'kmer_size' => '31',
        'cpus' => 1,
        'kmer_frequency_cutoff' => '1',
        'output_dir_and_file_prefix' => $build->data_directory.'/Escherichia_coli_TEST_WUGC'
    },
    'assembler params',
);

# ASSEMBLE
my $assemble = Genome::Model::Event::Build::DeNovoAssembly::Assemble->create(build => $build, model => $model);
ok($assemble, 'create assemble');
$assemble->dump_status_messages(1);
ok($assemble->execute, 'execute assemble');

ok(-s $assembler_params{config_file}, 'created config file');
my $config_fh = eval{ Genome::Sys->open_file_for_reading($assembler_params{config_file}); };
my $config = join('', $config_fh->getlines);
$config_fh->close;
my $expected_config = <<CONFIG;
max_rd_len=120
[LIB]
map_len=60
asm_flags=3
pair_num_cutoff=2
reverse_seq=0
avg_ins=260
CONFIG
$expected_config .= 'q1='.$build->data_directory.'/'.$build->file_prefix.".$library_id.forward.fastq\n";
$expected_config .= 'q2='.$build->data_directory.'/'.$build->file_prefix.".$library_id.reverse.fastq\n";
is($config, $expected_config, 'config matches');
my @file_exts = qw/ contig         gapSeq        links     peGrads
                    preGraphBasic  readOnContig  scafSeq   updated.edge
                    ContigIndex    edge          kmerFreq  newContigIndex
                    preArc         readInGap     scaf      scaf_gap        
                    vertex
                    /;
foreach my $ext ( @file_exts ) {
    my $example_file = $example_build->soap_output_file_for_ext($ext);
    ok(-s $example_file, "Example $ext file exists");
    my $file = $build->soap_output_file_for_ext($ext);
    ok(-s $file, "$ext file exists");
    is(File::Compare::compare($example_file, $file), 0, "$ext files match");
    #print 'ex: '.$example_file."\n";
    #print 'file: '.$file."\n\n";
}

# POST ASSEMBLE
my $post_assemble = Genome::Model::Event::Build::DeNovoAssembly::PostAssemble->create( build => $build, model => $model );
ok( $post_assemble, 'Created post assemble soap' );
ok( $post_assemble->execute, 'Executed post assemble soap' );
#check post asm output files
for my $file_name ( qw/ contigs.bases supercontigs.fasta supercontigs.agp / ) {
    my $example_file = $example_dir.'/edit_dir/'.$file_name;
    ok(-e $example_file, "$file_name example file exists");
    my $file = $build->data_directory.'/edit_dir/'.$file_name;
    ok(-e $file, "$file_name file exists");
    is(File::Compare::compare($file, $example_file), 0, "$file_name files match");
}

#METRICS/REPORT
my $metrics = Genome::Model::Event::Build::DeNovoAssembly::Report->create( build => $build, model => $model );
ok( $metrics, 'Created report' );
ok( $metrics->execute, 'Executed report' );
#check stats file
ok( -s $example_build->stats_file, 'Example build stats file exists' );
ok( -s $build->stats_file, 'Test created stats file' );
is(File::Compare::compare($example_build->stats_file,$build->stats_file), 0, 'Stats files match' );
#print 'gvimdiff '.join(' ', $example_build->stats_file,$build->stats_file)."\n"; <STDIN>;
#check build metrics
my %expected_metrics = (
    'n50_supercontig_length' => '101',
    'average_contig_length_gt_300' => '412',
    'reads_processed_success' => '0.934',
    'n50_contig_length_gt_300' => '439',
    'reads_assembled_success' => 'NA',
    'reads_assembled' => 'NA',
    'average_read_length' => '94',
    'reads_attempted' => 30000,
    'average_insert_size_used' => '260',
    'n50_contig_length' => '101',
    'genome_size_used' => '4500000',
    'reads_not_assembled_pct' => 'nan',
    'supercontigs' => '1407',
    'average_supercontig_length' => '115',
    'contigs' => '1411',
    'average_supercontig_length_gt_300' => '412',
    'average_contig_length' => '115',
    'major_contig_length' => '300',
    'n50_supercontig_length_gt_300' => '439',
    'reads_processed' => '28028',
    'assembly_length' => '162049',
    'read_depths_ge_5x' => 'NA'
);
for my $metric_name ( keys %expected_metrics ) {
    is($expected_metrics{$metric_name}, $build->$metric_name, "$metric_name matches" );
}

#print $build->data_directory."\n"; <STDIN>;
done_testing();
exit;

