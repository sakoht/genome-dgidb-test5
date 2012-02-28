#!/usr/bin/env perl

BEGIN {
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above 'Genome';

require File::Compare;
use Test::More;

# use
use_ok('Genome::Model::Build::AmpliconAssembly') or die;

# taxon, sample, lib
my $taxon = Genome::Taxon->create(
    name => 'Human Metagenome TEST',
    domain => 'Unknown',
    current_default_org_prefix => undef,
    estimated_genome_size => undef,
    current_genome_refseq_id => undef,
    ncbi_taxon_id => undef,
    ncbi_taxon_species_name => undef,
    species_latin_name => 'Human Metagenome',
    strain_name => 'TEST',
);
ok($taxon, 'create taxon');

my $sample = Genome::Sample->create(
    id => -1234,
    name => 'H_GV-933124G-S.MOCK',
    taxon_id => $taxon->id,
);
ok($sample, 'create sample');

my $library = Genome::Library->create(
    id => -12345,
    name => $sample->name.'-testlibs',
    sample_id => $sample->id,
);
ok($library, 'create library');

# inst data
my $inst_data_id = '01jan00.101amaa';
my $inst_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model/AmpliconAssembly/inst_data/'.$inst_data_id;
ok(-d $inst_data_dir, 'inst data dir') or die;
my $instrument_data = Genome::InstrumentData::Sanger->__define__(
    id => $inst_data_id,
    library => $library,
);
ok($instrument_data, 'create inst data') or die;
no warnings qw/ once redefine /;
*Genome::InstrumentData::Sanger::dump_to_file_system = sub{ return 1; };
*Genome::InstrumentData::Sanger::full_path = sub{ return $inst_data_dir; };
use warnings;
ok(-d $instrument_data->full_path, 'full path');

# pp
my $pp = Genome::ProcessingProfile->__define__(
    type_name => 'amplicon assembly',
    name => '__TEST_AA__',
    assembler => 'phredphrap',
    assembly_size => 1465,
    primer_amp_forward => '18SEUKF:ACCTGGTTGATCCTGCCAG',
    primer_amp_reverse => '18SEUKR:TGATCCTTCYGCAGGTTCAC',
    primer_seq_forward => '502F:GGAGGGCAAGTCTGGT',
    primer_seq_reverse => '1174R:CCCGTGTTGAGTCAAA',
    purpose => 'composition',
    region_of_interest => '16S',
    sequencing_center => 'gsc',
    sequencing_platform => 'sanger',
);
ok($pp, 'define pp') or die;

# model
my $model = Genome::Model::AmpliconAssembly->create(
    processing_profile => $pp,
    subject_name => $sample->name,
    subject_type => 'sample_name'
);
ok($model, 'create model') or die;
ok($model->add_instrument_data($instrument_data), 'add inst data to model');

my $example_build = Genome::Model::Build->create(
    model=> $model,
    data_directory => '/gsc/var/cache/testsuite/data/Genome-Model/AmpliconAssembly/build',
    id => -2288
);
ok($example_build, 'example build') or die;
ok($example_build->get_or_create_data_directory, 'resolved data dir');
ok(-d $example_build->data_directory, 'example build dir exists');

my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
my $build = Genome::Model::Build::AmpliconAssembly->create(
    id => -1199,
    model => $model,
    data_directory => $tmpdir,
);
isa_ok($build, 'Genome::Model::Build::AmpliconAssembly');
ok($build->get_or_create_data_directory, 'resolved data dir');

# calculated kb
is($build->calculate_estimated_kb_usage, 512_000, 'Estimated kb usage');

# dirs
#ok($build->create_subdirectories, 'created subdirectories');
for my $subdir (qw/ chromat_dir phd_dir edit_dir /) {
    my $dir = $build->$subdir;
    ok(-d $dir, "$subdir was created");
}

# fastas
my $fasta_base = $build->fasta_dir."/".$sample->name;
my %file_methods_and_results = (
    processed_fasta_file => $fasta_base.'.assembly.fasta',
    oriented_fasta_file => $fasta_base.'.oriented.fasta',
);
for my $file_name ( keys %file_methods_and_results ) {
    is($build->$file_name, $file_methods_and_results{$file_name}, $file_name);
}

# Verify Instrument Data
my $verify_instrument_data = Genome::Model::Event::Build::AmpliconAssembly::VerifyInstrumentData->create(
    model => $model,
    build => $build,
);
ok($verify_instrument_data, 'create verify instrument data');
ok($verify_instrument_data->execute, 'execute verify instrument data');

# Prepare Instrument Data
my $prepare_instrument_data = Genome::Model::Event::Build::AmpliconAssembly::PrepareInstrumentData->create(
    model => $model,
    build => $build,
);
ok($prepare_instrument_data, 'create prepare instrument data');
ok($prepare_instrument_data->execute, 'execute prepare instrument data');

# Trim and Screen
my $trim_and_screen = Genome::Model::Event::Build::AmpliconAssembly::TrimAndScreen->create(
    model => $model,
    build => $build,
);
ok($trim_and_screen, 'create trim and screen');
ok($trim_and_screen->execute, 'execute trim and screen');

# Assemble
my $assemble = Genome::Model::Event::Build::AmpliconAssembly::Assemble->create(
    model => $model,
    build => $build,
);
ok($assemble, 'create assemble');
ok($assemble->execute, 'execute assemble');

# Classify
my $classify = Genome::Model::Event::Build::AmpliconAssembly::Classify->create(
    model => $model,
    build => $build,
);
ok($classify, 'create classify');
ok($classify->execute, 'execute classify');

# Orient
my $orient = Genome::Model::Event::Build::AmpliconAssembly::Orient->create(
    model => $model,
    build => $build,
);
ok($orient, 'create orient');
ok($orient->execute, 'execute orient');

# Collate
my $collate = Genome::Model::Event::Build::AmpliconAssembly::Collate->create(
    model => $model,
    build => $build,
);
ok($collate, 'create collate');
ok($collate->execute, 'execute collate');
ok(-s $build->processed_fasta_file, 'processed fasta file');
ok(-s $build->oriented_fasta_file, 'oriented fasta file');

# Reports
my $reports = Genome::Model::Event::Build::AmpliconAssembly::Reports->create(
    model => $model,
    build => $build,
);
ok($reports, 'create reports');
ok($reports->execute, 'execute reports');
ok($build->get_report('Stats'), 'got stats report');
ok($build->get_report('Composition'), 'got composition report');

#print $build->data_directory."\n";<STDIN>;
done_testing();
exit;

