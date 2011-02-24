#!/usr/bin/env perl

use strict;
use warnings;

use above "Genome";

use Test::More;
use File::Temp;

$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
$ENV{UR_DBI_NO_COMMIT} = 1;

my $s = Genome::Sample->get(2824113551);
ok($s, 'loaded sample data');

my $library_name = "Pooled_Library-2010-02-10_2";

my $dummy_id = UR::DataSource->next_dummy_autogenerated_id -1;

my $reference_sequence_build = Genome::Model::Build::ImportedReferenceSequence->get(name => "NCBI-human-build36");
my $source_data_file = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Command-Import-Genotype/SCENA_p_TCGAb29and30_SNP_N_GenomeWideSNP_6_A02_569132.small.genotype';
my $library = Genome::Library->get(name => $library_name);
my $sample = Genome::Sample->get(id => $library->sample_id);
my $sample_name = $sample->name;
ok($sample, "found sample $sample_name")
    or die "exiting because the sample does not exist";

my $tmp_dir = File::Temp::tempdir('Genome-InstrumentData-Commnd-Import-Genotype-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my %params = (
    reference_sequence_build => $reference_sequence_build,
    library => $library,
    source_data_file => $source_data_file,
    define_model => 1,
    sequencing_platform => "unit test industries",
    description => 'TEST Import genotype file',
);

no warnings;
*UR::Context::commit = sub { return 1 }; # NO_COMMIT not respected by G:M:C:Services:Build:Run
*Genome::Report::Email::send_report = sub{ return 1; }; # so we don't get emails
use warnings;

# Fail - no ref build
delete $params{reference_sequence_build};
my $cmd = Genome::InstrumentData::Command::Import::Genotype->create(%params);
$cmd->dump_status_messages(1);
ok(!$cmd->execute, "failed as expected - w/o reference build"); 
$cmd->delete;
$params{reference_sequence_build} = $reference_sequence_build;

# Fail - no sample/library
delete $params{library};
$cmd = Genome::InstrumentData::Command::Import::Genotype->create(%params);
$cmd->dump_status_messages(1);
ok(!$cmd->execute, "failed as expected - w/o sample or library"); 
$cmd->delete;
$params{library} = $library;

# Fail - no file
delete $params{source_data_file};
$cmd = Genome::InstrumentData::Command::Import::Genotype->create(%params);
$cmd->dump_status_messages(1);
ok(!$cmd->execute, "failed as expected - w/o sample or library"); 
$cmd->delete;
$params{source_data_file} = $source_data_file;

# Success
$cmd = Genome::InstrumentData::Command::Import::Genotype->create(%params);
ok($cmd, "constructed an import command");
$cmd->dump_status_messages(1);
my @errors = $cmd->__errors__;
is(scalar(@errors),0, "no errors in cmd");
ok($cmd->execute, "execution was successful");

my $i = Genome::InstrumentData::Imported->get($cmd->generated_instrument_data_id);
is($i->import_format, 'genotype file', 'import format');
ok(!$i->import_source_name, 'import source name');
is($i->description, $params{description}, 'description');
is($i->library_id, $library->id, 'description');

my $disk = Genome::Disk::Allocation->get(owner_class_name => $i->class, owner_id => $i->id);
ok($disk, "found an allocation owned by the new instrument data");
my $owner_class = $disk->owner_class_name;
is($owner_class, "Genome::InstrumentData::Imported", "allocation belongs to  G::I::Imported");
is($disk->owner_id, $i->id, "allocation owner ID matches imported instrument data id");
ok(-e $i->data_directory, "output directory is present");
is($i->library_id,$library->id,"library_id matches");

my $genotype_file = $i->genotype_microarray_file_for_subject_and_version(
    $reference_sequence_build->subject_name, $reference_sequence_build->version
);
ok($genotype_file, 'got genotype file');
ok(-s $genotype_file, "genotype file exists");

my $model = Genome::Model::GenotypeMicroarray->get(
    subject_id => $sample->id,
    processing_profile_id => 2186707,
);
ok($model, 'created model');
my $build = $model->last_complete_build;
ok($build, 'created build');
my $snp_array_file = $build->formatted_genotype_file_path;
ok(-s $snp_array_file, 'created snp array file');

# Fail - model exists
$cmd = Genome::InstrumentData::Command::Import::Genotype->create(%params);
$cmd->dump_status_messages(1);
ok(!$cmd->execute, "fail as expected - recreate model"); 
$cmd->delete;

done_testing();
exit;

