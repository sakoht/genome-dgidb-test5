#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';
use Test::More tests => 8;

use_ok('Genome::Model::SomaticValidation::Command::ManualResult');

my $temp_build_data_dir = File::Temp::tempdir('t_SomaticValidation_Build-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my $temp_dir = File::Temp::tempdir('Model-Command-Define-SomaticValidation-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);


my $somatic_variation_build = &setup_somatic_variation_build;
isa_ok($somatic_variation_build, 'Genome::Model::Build::SomaticVariation', 'setup test somatic variation build');

my $data = <<EOBED
1	10003	10004	A/T
EOBED
;
my $revised_bed_file = Genome::Sys->create_temp_file_path;
Genome::Sys->write_file($revised_bed_file, $data);
ok(-s $revised_bed_file, 'created a revised bed file');


my $cmd = Genome::Model::SomaticValidation::Command::ManualResult->create(
    variant_file => $revised_bed_file,
    variant_type => 'snv',
    source_build => $somatic_variation_build,
    description => 'curated for testing purposes',
);
isa_ok($cmd, 'Genome::Model::SomaticValidation::Command::ManualResult', 'created command');
ok($cmd->execute, 'executed command');

my $result = $cmd->manual_result;
isa_ok($result, 'Genome::Model::Tools::DetectVariants2::Result::Manual', 'created manual result');
is($result->sample, $somatic_variation_build->tumor_model->subject, 'result has expected sample');
is($result->control_sample, $somatic_variation_build->normal_model->subject, 'result has expected control sample');


sub setup_somatic_variation_build {
    my $test_profile = Genome::ProcessingProfile::ReferenceAlignment->create(
        name => 'test_profile',
        sequencing_platform => 'solexa',
        dna_type => 'cdna',
        read_aligner_name => 'bwa',
        snv_detection_strategy => 'samtools',
    );

    my $test_individual = Genome::Individual->create(
        common_name => 'TEST',
        name => 'test_individual',
    );

    my $test_sample = Genome::Sample->create(
        name => 'test_subject',
        source_id => $test_individual->id,
    );

    my $test_control_sample = Genome::Sample->create(
        name => 'test_control_subject',
        source_id => $test_individual->id,
    );

    my $test_instrument_data = Genome::InstrumentData::Solexa->create(
    );

    my $reference_sequence_build = Genome::Model::Build::ReferenceSequence->get_by_name('NCBI-human-build36');

    my $test_model = Genome::Model->create(
        name => 'test_reference_aligment_model_TUMOR',
        subject_name => 'test_subject',
        subject_type => 'sample_name',
        processing_profile_id => $test_profile->id,
        reference_sequence_build => $reference_sequence_build,
    );

    my $add_ok = $test_model->add_instrument_data($test_instrument_data);

    my $test_build = Genome::Model::Build->create(
        model_id => $test_model->id,
        data_directory => $temp_build_data_dir,
    );

    my $test_model_two = Genome::Model->create(
        name => 'test_reference_aligment_model_mock_NORMAL',
        subject_name => 'test_control_subject',
        subject_type => 'sample_name',
        processing_profile_id => $test_profile->id,
        reference_sequence_build => $reference_sequence_build,
    );

    $add_ok = $test_model_two->add_instrument_data($test_instrument_data);

    my $test_build_two = Genome::Model::Build->create(
        model_id => $test_model_two->id,
        data_directory => $temp_build_data_dir,
    );

    my $test_somvar_pp = Genome::ProcessingProfile::SomaticVariation->create(
        name => 'test somvar pp',
        snv_detection_strategy => 'samtools r599 [--test=1]',
        tiering_version => 1,
    );

    my $annotation_build = Genome::Model::Build::ImportedAnnotation->__define__(
        model_id => '-1',
    );

    my $somvar_model = Genome::Model::SomaticVariation->create(
        tumor_model => $test_model,
        normal_model => $test_model_two,
        name => 'test somvar model',
        processing_profile => $test_somvar_pp,
        annotation_build => $annotation_build,
    );

    my $somvar_build = Genome::Model::Build::SomaticVariation->__define__(
        model_id => $somvar_model->id,
        data_directory => $temp_build_data_dir,
        tumor_build => $test_build_two,
        normal_build => $test_build,
    );

    my $dir = ($temp_dir . '/' . 'fake_samtools_result');
    Genome::Sys->create_directory($dir);
    my $result = Genome::Model::Tools::DetectVariants2::Result->__define__(
        detector_name => 'the_bed_detector',
        detector_version => 'r599',
        detector_params => '--fake',
        output_dir => Cwd::abs_path($dir),
        id => -2013,
    );

    my $data = <<EOBED
1	10003	10004	A/T
2	8819	8820	A/G
EOBED
;
    my $bed_file = $dir . '/snvs.hq.bed';
    Genome::Sys->write_file($bed_file, $data);

    $result->add_user(user => $somvar_build, label => 'uses');

    return $somvar_build;
}

