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

use_ok('Genome::Model::DeNovoAssembly::Report::Summary') or die;

my $base_dir = '/gsc/var/cache/testsuite/data/Genome-Model/DeNovoAssembly';
my $archive_path = $base_dir.'/inst_data/-7777/archive.tgz';
ok(-s $archive_path, 'inst data archive path') or die;
my $example_dir = $base_dir.'/velvet_v10';
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

my $pp = Genome::ProcessingProfile::DeNovoAssembly->get(2354215); #apipe-test-de_novo_velvet_solexa
ok($pp, 'pp') or die;

my $model = Genome::Model::DeNovoAssembly->create(
    processing_profile => $pp,
    subject_name => $taxon->name,
    subject_type => 'species_name',
    center_name => 'WUGC',
);
ok($model, 'de novo model') or die;
ok($model->add_instrument_data($instrument_data), 'add inst data to model');

my $build = Genome::Model::Build->create(
    model => $model,
    data_directory => $example_dir,
);
ok($build, 'create example build');

my $generator = Genome::Model::DeNovoAssembly::Report::Summary->create(
    build_id => $build->id,
);
ok($generator, 'Created generator');
my $report = $generator->generate_report;
ok($report, 'Generated report');

done_testing();
exit;

