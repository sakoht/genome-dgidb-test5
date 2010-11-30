#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use above 'Genome';
use Test::More;
use Carp::Always;
use Data::Dumper;

my $model_class = 'Genome::Model::Command::Define::ReferenceAlignment';
my $model_name = "test-define-refalign-model-$$";
use_ok($model_class);

# set up required test data
my $individual = Genome::Individual->create(name => 'test-patient', common_name => 'testpatient');
my $sample = Genome::Sample->create(name => 'test-patient', species_name => 'human', common_name => 'normal', source => $individual);
my ($rbuild, $abuild) = create_reference_builds(); # (reference_build, annotation_build)
my $pp = Genome::ProcessingProfile::ReferenceAlignment->create(
    name => 'test_profile',
    sequencing_platform => 'solexa',
    dna_type => 'cdna',
    read_aligner_name => 'bwa',
    snv_detector_name => 'samtools',
    );
ok($pp, 'created ReferenceAlignment processing profile');


# begin testing
my $cmd = Genome::Model::Command::Define::ReferenceAlignment->create();
ok($cmd && $cmd->__errors__, 'insufficient parameters generate errors');

# use default reference sequence
my %params = (
    subject_name => $sample->name,
    processing_profile_id => $pp->id,
);
for my $model (create_direct_and_cmdline(%params)) {
    ok($model->reference_sequence_build, 'some default exists for reference sequence');
    ok(!$model->annotation_reference_build, 'annotation build is not defined');
    $model->delete;
}

# specify reference sequence by id
%params = (
    subject_name => $sample->name,
    processing_profile_name => $pp->name,
    reference_sequence_build => $rbuild->id,
);
for my $model (create_direct_and_cmdline(%params)) {
    is($model->reference_sequence_build->id, $rbuild->id, 'reference sequence id correct');
    ok(!$model->annotation_reference_build, 'annotation build is not defined');
    ok($model->delete, 'deleted model');
}

# specify reference sequence by name
%params = (
    subject_name => $sample->name,
    processing_profile_id => $pp->id,
    reference_sequence_build => $rbuild->name,
);
for my $model (create_direct_and_cmdline(%params)) {
    is($model->reference_sequence_build->id, $rbuild->id, 'reference sequence id correct');
    ok(!$model->annotation_reference_build, 'annotation build is not defined');
    ok($model->delete, 'deleted model');
}

# specify reference sequence by object
%params = (
    subject_name => $sample->name,
    processing_profile_name => $pp->name,
    reference_sequence_build => $rbuild,
);
for my $model (create_direct_and_cmdline(%params)) {
    is($model->reference_sequence_build->id, $rbuild->id, 'reference sequence id correct');
    ok(!$model->annotation_reference_build, 'annotation build is not defined');
    ok($model->delete, 'deleted model');
}

# specify annotation build by id
%params = (
    subject_name => $sample->name,
    processing_profile_id => $pp->id,
    reference_sequence_build => $rbuild->name,
    annotation_reference_build => $abuild->id,
);
for my $model (create_direct_and_cmdline(%params)) {
    ok($model->annotation_reference_build, 'annotation build is defined');
    is($model->annotation_reference_build->id, $abuild->id, 'annotation build id correct');
    ok($model->delete, 'deleted model');
}

# specify annotation build by name
%params = (
    subject_name => $sample->name,
    processing_profile_id => $pp->id,
    reference_sequence_build => $rbuild->name,
    annotation_reference_build => $abuild->name,
);
for my $model (create_direct_and_cmdline(%params)) {
    ok($model->annotation_reference_build, 'annotation build is defined');
    is($model->annotation_reference_build->id, $abuild->id, 'annotation build id correct');
    ok($model->delete, 'deleted model');
}

# specify annotation build by object
%params = (
    subject_name => $sample->name,
    processing_profile_id => $pp->id,
    reference_sequence_build => $rbuild->name,
    annotation_reference_build => $abuild,
);
for my $model (create_direct_and_cmdline(%params)) {
    ok($model->annotation_reference_build, 'annotation build is defined');
    is($model->annotation_reference_build->id, $abuild->id, 'annotation build id correct');
    ok($model->delete, 'deleted model');
}

# now test the legacy processing profile parameter annotation_reference_transcripts. once migration to the
# model input is complete, this can go away.
ok($pp->annotation_reference_transcripts($abuild->name));
is($abuild->name, $pp->annotation_reference_transcripts($abuild->name),
    "updated legacy annotation_reference_transcripts parameter on processing profile");

my $model = create_direct(
    subject_name => $sample->name,
    processing_profile_id => $pp->id,
    reference_sequence_build => $rbuild->id,
);
ok($model, 'created model with reference sequence id and legacy annotation_reference_transcripts from processing profile');
is($model->reference_sequence_build->id, $rbuild->id, 'reference sequence id correct');
ok($model->annotation_reference_build, 'annotation build is defined');
is($model->annotation_reference_build->id, $abuild->id, 'annotation build id correct');
ok($model->delete, 'deleted model');

done_testing();

sub make_argv {
    my %argv = @_;
    return map {
        my ($k, $v) = ($_, $argv{$_});
        $k =~ s/_/-/g;
        $v = $v->id if ref($v) and $v->can('id');
        "--$k=$v";
    } keys %argv; 
}

sub create_cmdline {
    my @args = (@_, "--model-name=$model_name-cmdline");
    my $rv = $model_class->_execute_with_shell_params_and_return_exit_code(@args);
    is($rv, 0, "create via command line ok (" . join(',', @args) . ")");
    return Genome::Model->get(name => "$model_name-cmdline");
}

sub create_direct {
    my %args = (@_, model_name => "$model_name-direct");
    my $specified = join(',', keys %args);
    my $cmd = $model_class->create(%args);
    ok($cmd && !$cmd->__errors__, "created command without errors (specified $specified)");
    ok($cmd->execute, "command executed ok");
    return Genome::Model->get($cmd->result_model_id);
}

sub create_direct_and_cmdline {
    my $direct = create_direct(@_);
    ok($direct, "created model directly");
    my $cmdline = create_cmdline(make_argv(@_));
    ok($cmdline, "created model via command line");
    return ($direct, $cmdline);
}

sub create_reference_builds {
    my $reference_version  =    '34';
    my $annotation_version = '12_34x';
    my $data_dir = File::Temp::tempdir('DefineReferenceAlignmentTest-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);

    my $ref_pp = Genome::ProcessingProfile::ImportedReferenceSequence->create(name => 'test_ref_pp');
    my $ref_model = Genome::Model::ImportedReferenceSequence->create(
        name                => 'test_ref_sequence',
        processing_profile  => $ref_pp,
        subject_class_name  => ref($sample),
        subject_id          => $sample,
    );
    my $rbuild = Genome::Model::Build::ImportedReferenceSequence->create(
        name            => 'test_ref_sequence_build',
        model           => $ref_model,
        fasta_file      => 'nofile', 
        data_directory  => $data_dir,
        version         => $reference_version,
    );
    ok($rbuild, 'created reference sequence build');

    my $ann_pp = Genome::ProcessingProfile::ImportedAnnotation->create(name => 'test_ann_pp', annotation_source => 'test_source');
    my $ann_model = Genome::Model::ImportedAnnotation->create(
        name                => 'test_annotation',
        processing_profile  => $ann_pp,
        subject_class_name  => ref($sample),
        subject_id          => $sample->id,
    );

    my $abuild = Genome::Model::Build::ImportedAnnotation->create(
        model           => $ann_model,
        data_directory  => $data_dir,
        version         => $annotation_version,
    );
    ok($abuild, 'created annotation build');

    # make sure the annotation build is 'completed' and has status 'Succeeded '
    my $abuild_event = Genome::Model::Event::Build->create(
        model_id => $abuild->model->id,
        build_id => $abuild->id,
        event_type => 'genome model build',
        event_status => 'Succeeded',
        date_completed => UR::Time->now,
    );

    return ($rbuild, $abuild);
}


