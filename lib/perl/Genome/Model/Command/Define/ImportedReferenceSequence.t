#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use above 'Genome';
use Test::More tests => 27;

my $cmd_class = 'Genome::Model::Command::Define::ImportedReferenceSequence';
use_ok($cmd_class);

my $data_dir = File::Temp::tempdir('ImportedAnnotationTest-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my $pp = Genome::ProcessingProfile::ImportedReferenceSequence->create(name => 'test_ref_pp');
my $patient = Genome::Individual->create(name => "test-patient", common_name => 'testpat');
my $sample = Genome::Sample->create(name => "test-patient", species_name => 'human', common_name => 'tumor', source => $patient);
ok($sample, 'created sample');

my $sequence_uri = "http://genome.wustl.edu/foo/bar/test.fa.gz";

my $fasta_file = "$data_dir/data.fa";
my $fasta_fh = new IO::File(">$fasta_file");
$fasta_fh->write(">HI\nNACTGACTGNNACTGN");
$fasta_fh->close();

my @params = (
    "--fasta-file=$fasta_file",
    "--model-name=test-ref-seq-1",
    "--processing-profile-id=".$pp->id,
    "--species-name=human",
    "--subject-id=".$sample->id,
    "--version=42",
    "--sequence-uri=".$sequence_uri,
    );

my $rv = $cmd_class->_execute_with_shell_params_and_return_exit_code(@params);
is($rv, 0, 'executed command');
my $model = Genome::Model::ImportedReferenceSequence->get(name => 'test-ref-seq-1');
ok($model, 'Found newly created model');
my $build = $model->last_complete_build;
ok($build, 'Found a completed build');
is($build->version, 42, 'Build has correct version');
is($build->sequence_uri, $sequence_uri, "sequence uri matches");

# specify derived_from
@params = (
    "--derived-from=".$build->name,
    "--fasta-file=$fasta_file",
    "--model-name=test-ref-seq-2",
    "--processing-profile-id=".$pp->id,
    "--species-name=human",
    "--subject-id=".$sample->id,
    "--version=26",
    "--sequence-uri=".$sequence_uri,
    );
$rv = $cmd_class->_execute_with_shell_params_and_return_exit_code(@params);
is($rv, 0, 'executed command');
my $coords_model = Genome::Model::ImportedReferenceSequence->get(name => 'test-ref-seq-2');
ok($coords_model, 'Found newly created model');
my $d1_build = $coords_model->last_complete_build;
ok($d1_build, 'Found a completed build');
is($d1_build->version, 26, 'Build has correct version');
is($d1_build->derived_from->id, $build->id, 'derived_from property is correct');
is($d1_build->coordinates_from->id, $build->id, 'coordinates_from property is correct');
ok($d1_build->is_compatible_with($build), 'coordinates_from build is_compatible_with parent build');
is($d1_build->sequence_uri, $sequence_uri, "sequence uri matches");
ok($build->is_compatible_with($d1_build), 'parent build is_compatible_with coordinates_from build');

# derive from d1_build
@params = (
    "--derived-from=".$d1_build->id,
    "--fasta-file=$fasta_file",
    "--model-name=test-ref-seq-3",
    "--processing-profile-id=".$pp->id,
    "--species-name=human",
    "--subject-id=".$sample->id,
    "--version=96",
    "--sequence-uri=".$sequence_uri,
    );
$rv = $cmd_class->_execute_with_shell_params_and_return_exit_code(@params);
is($rv, 0, 'executed command');
my $derived_model = Genome::Model::ImportedReferenceSequence->get(name => 'test-ref-seq-3');
ok($derived_model, 'Found newly created model');
my $d2_build = $derived_model->last_complete_build;
ok($d2_build, 'Found a completed build');
is($d2_build->version, 96, 'Build has correct version');
is($d2_build->derived_from->id, $d1_build->id, 'derived_from property is correct');
is($d2_build->coordinates_from->id, $build->id, 'coordinates_from property is correct');
ok($d2_build->is_compatible_with($d1_build), 'derived build is_compatible_with parent build');
ok($d1_build->is_compatible_with($d2_build), 'derived build is_compatible_with parent build');
ok($d2_build->is_compatible_with($build), 'derived build is_compatible_with parent build');
is($d2_build->sequence_uri, $sequence_uri, "sequence uri matches");
ok($build->is_compatible_with($d2_build), 'parent build is_compatible_with derived build');
