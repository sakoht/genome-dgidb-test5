#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';

use Test::More;
use File::Spec;

if(Genome::Config->arch_os() =~ '64') {
    plan tests => 26;
} else {
    plan skip_all => 'Must be run on a 64-bit machine',
}

$ENV{GENOME_MODEL_TESTDIR} = Genome::Sys->create_temp_directory;

use_ok('Genome::Model::Command::Define::ImportedReferenceSequence');

my $test_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Command-Define-ImportedReferenceSequence/';


#First test--a 42MB FASTA with 2 chromosomes
#The test on a larger file is useful to test the chunking algorithm used in producing the bases files
my $first_test_dir = $test_data_dir . '1/';
my $first_fasta = $first_test_dir . 'all_sequences.fa';

ok(Genome::Sys->check_for_path_existence($first_fasta), 'First test FASTA exists');

my $first_define_command = Genome::Model::Command::Define::ImportedReferenceSequence->create(
    fasta_file => $first_fasta,
    prefix => 'imported_reference_testsuite',
    species_name => 'none',
    on_warning => 'exit',
    job_dispatch => 'inline', #can't spawn off LSF jobs with UR_DBI_NO_COMMIT enabled
    server_dispatch => 'inline',
    version => '42mb',
    sequence_uri => 'http://foo.bar.com',
);

ok($first_define_command, 'created define command');
$DB::single = 1;
ok($first_define_command->execute, 'executed define command');

my $first_model_id = $first_define_command->result_model_id;
my $first_model = Genome::Model->get($first_model_id);
isa_ok($first_model, 'Genome::Model::ImportedReferenceSequence');

my @first_builds = $first_model->builds;
is(scalar(@first_builds), 1, 'Created a model with one build');

my $first_data_directory = $first_builds[0]->data_directory;
my $first_build_fasta = $first_data_directory . '/all_sequences.fa';

my $first_fasta_diff = Genome::Sys->diff_file_vs_file($first_fasta, $first_build_fasta);
ok(!$first_fasta_diff, 'FASTA copied to build')
    or diag("  diff:\n" . $first_fasta_diff);

my $first_build_1_bases = $first_data_directory . '/1.bases';
my $first_1_bases = $first_test_dir . '/1.bases';
my $first_1_bases_diff = Genome::Sys->diff_file_vs_file($first_1_bases, $first_build_1_bases);
ok(!$first_1_bases_diff, '1.bases generated as expected')
    or diag("  diff\n" . $first_1_bases_diff);

my $first_build_2_bases = $first_data_directory . '/2.bases';
my $first_2_bases = $first_test_dir . '/2.bases';
my $first_2_bases_diff = Genome::Sys->diff_file_vs_file($first_2_bases, $first_build_2_bases);
ok(!$first_2_bases_diff, '2.bases generated as expected')
    or diag("  diff\n" . $first_2_bases_diff);

my @files = glob($first_data_directory . '/*');
is(scalar(@files), 7, 'Produced 7 files/directories');

#Later tests on a smaller dataset will actually compare all the files
my %expected_file_sizes = (
    '1.bases' => 20971520,
    '2.bases' => 20971520,
    'all_sequences.bfa' => 20971548,
    'all_sequences.fa' => 42467426,
    'all_sequences.fa.amb' => 13,
    'all_sequences.fa.ann' => 147,
    'all_sequences.fa.bwt' => 15728676,
    'all_sequences.fa.fai' => 46,
    'all_sequences.fa.pac' => 10485762,
    'all_sequences.fa.rbwt' => 15728676,
    'all_sequences.fa.rpac' => 10485762,
    'all_sequences.fa.rsa' => 5242908,
    'all_sequences.fa.sa' => 5242908,
    'all_sequences.bowtie' => 42467426,
    'all_sequences.bowtie.1.ebwt' => 16178321,
    'all_sequences.bowtie.2.ebwt' => 5242888,
    'all_sequences.bowtie.3.ebwt' => 26,
    'all_sequences.bowtie.4.ebwt' => 10485760,
    'all_sequences.bowtie.fa' => 42467426,
    'all_sequences.bowtie.fa.fai' => 46,
    'all_sequences.bowtie.fai' => 46,
    'all_sequences.bowtie.rev.1.ebwt' => 16178321,
    'all_sequences.bowtie.rev.2.ebwt' => 5242888,
);

my @files_to_test = grep(-f $_ && $_ !~ 'build.xml' && $_ !~ 'manifest.tsv', @files);

for my $file (@files_to_test) {
    my ($vol, $dir, $file_base) = File::Spec->splitpath($file);
    is(-s $file, $expected_file_sizes{$file_base}, 'Generated ' . $file . ' matches expected size');
}

#Second test--a tiny FASTA with 3 chromosomes
#updated from 2.02 to 2.03 to create manifest.tsv
my $second_test_dir = $test_data_dir . '2.04/';
my $second_fasta = $second_test_dir . 'all_sequences.fa';

ok(Genome::Sys->check_for_path_existence($second_fasta), 'Second test FASTA exists');

my $second_define_command = Genome::Model::Command::Define::ImportedReferenceSequence->create(
    fasta_file => $second_fasta,
    prefix => 'imported_reference_testsuite',
    species_name => 'none',
    on_warning => 'exit',
    job_dispatch => 'inline', #can't spawn off LSF jobs with UR_DBI_NO_COMMIT enabled
    server_dispatch => 'inline',
    version => 't1',
    sequence_uri => 'http://foo.bar.com',
);

ok($second_define_command, 'created define command');
ok($second_define_command->execute, 'executed define command');

my $second_model_id = $second_define_command->result_model_id;
my $second_model = Genome::Model->get($second_model_id);
isa_ok($second_model, 'Genome::Model::ImportedReferenceSequence');
is($second_model, $first_model, 'Returned same model as before');

my @second_builds = $second_model->builds;
is(scalar(@second_builds), 2, 'Added a new build to the same model');

my $second_build = $second_model->build_by_version('t1');
isa_ok($second_build, 'Genome::Model::Build::ImportedReferenceSequence');
my $second_data_directory = $second_build->data_directory;

my $diff_fh = IO::File->new("diff -r -q $second_test_dir $second_data_directory |");
my @diff = <$diff_fh>;

@diff = grep { $_ !~ 'build.xml' }
        grep { $_ !~ 'reports' }
        grep { $_ !~ 'logs' } 
        grep { $_ !~ 'manifest' } @diff;

ok(!scalar(@diff), 'Build directory matches expected result')
    or diag( join("\n", '  diff: ', @diff) );

#Third test--complain about adding a second reference of the same name and version
my $third_define_command = Genome::Model::Command::Define::ImportedReferenceSequence->create(
    fasta_file => $second_fasta,
    prefix => 'imported_reference_testsuite',
    species_name => 'none',
    on_warning => 'exit',
    job_dispatch => 'inline', #can't spawn off LSF jobs with UR_DBI_NO_COMMIT enabled
    server_dispatch => 'inline',
    version => 't1',
    sequence_uri => 'http://foo.bar.com',
);
ok($third_define_command, 'created define command');
ok(!$third_define_command->execute, 'execute prevented duplicate build creation');

#Fourth test--fail off due to invalid taxon
my $fourth_define_command = Genome::Model::Command::Define::ImportedReferenceSequence->create(
    fasta_file => $second_fasta,
    prefix => 'imported_reference_testsuite',
    species_name => 'nonexistent_species_name_for_testcase',
    on_warning => 'exit',
    job_dispatch => 'inline', #can't spawn off LSF jobs with UR_DBI_NO_COMMIT enabled
    server_dispatch => 'inline',
    version => 't4',
    sequence_uri => 'http://foo.bar.com',
);
ok($fourth_define_command, 'created define command');
ok(!$fourth_define_command->execute, 'execute prevented using invalid taxon');


#Fifth test--fail off due to existing model name
my $fifth_define_command = Genome::Model::Command::Define::ImportedReferenceSequence->create(
    fasta_file => $second_fasta,
    prefix => 'apipe',
    species_name => 'none',
    on_warning => 'exit',
    job_dispatch => 'inline', #can't spawn off LSF jobs with UR_DBI_NO_COMMIT enabled
    server_dispatch => 'inline',
    model_name => 'apipe-test-01-somatic',
    sequence_uri => 'http://foo.bar.com',
);
ok($fifth_define_command, 'created define command');
ok(!$fifth_define_command->execute, 'execute prevented creating a model due to existing non-reference model');
