#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use above 'Genome';

require Genome::InstrumentData::Solexa;
use Test::More tests => 138;
use Test::MockObject;

use_ok('Genome::Model::Command::Services::AssignQueuedInstrumentData') or die;

my $gsc_project = Test::MockObject->new();
ok($gsc_project, 'create mock gsc project');
$gsc_project->set_isa('Genome::Site::WUGC::SetupProjectResearch');
$gsc_project->set_always(id => -4444);
$gsc_project->set_always(name => 'AQID-test-project');
$gsc_project->set_always(setup_name => 'AQID-test-project');
$gsc_project->set_always( pse_id => '-10000001');

my $gsc_workorder = Test::MockObject->new();
ok($gsc_workorder, 'create mock work order');
$gsc_workorder->set_isa('Genome::Site::WUGC::SetupWorkOrder');
$gsc_workorder->set_always(id => -1111);
$gsc_workorder->set_always(name => 'AQID-Test-Workorder');
$gsc_workorder->set_always(setup_name => 'AQID-Test-Workorder');
$gsc_workorder->set_always(get_project => $gsc_project);
$gsc_workorder->set_always(pipeline => undef); #TODO: am I ok?

my $taxon = Genome::Taxon->get( species_name => 'human' );
my $individual = Genome::Individual->create(
    id => '-10',
    name => 'AQID-test-individual',
    common_name => 'AQID10',
    taxon_id => $taxon->id,
);

my $sample = Genome::Sample->create(
    id => '-1',
    name => 'AQID-test-sample',
    common_name => 'normal',
    source_id => $individual->id,
);

my $library = Genome::Library->create(
    id => '-2',
    name => 'test library',
    sample_id => $sample->id,
);

isa_ok($library, 'Genome::Library');
isa_ok($sample, 'Genome::Sample');

my $ii = Test::MockObject->new();

$ii->set_always('copy_sequence_files_confirmed_successfully', 1);
$ii->set_always('get_work_orders', ($gsc_workorder));
no warnings;
*Genome::InstrumentData::Solexa::index_illumina = sub{ return $ii };
use warnings;
my $instrument_data_1 = Genome::InstrumentData::Solexa->create(
    id => '-100',
    library_id => $library->id,
    flow_cell_id => 'TM-021',
    lane => '1',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);
ok($instrument_data_1, 'Created an instrument data');

my $processing_profile = Genome::ProcessingProfile::ReferenceAlignment->create(
    dna_type => 'genomic dna',
    name => 'AQID-test-pp',
    read_aligner_name => 'bwa',
    sequencing_platform => 'solexa',
    read_aligner_params => '#this is a test',
    transcript_variant_annotator_version => 1,
);
ok($processing_profile, 'Created a processing_profile');

my $ref_seq_build = Genome::Model::Build::ImportedReferenceSequence->get(name => 'NCBI-human-build36');
isa_ok($ref_seq_build, 'Genome::Model::Build::ImportedReferenceSequence') or die;

my $pse_1 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-12345',
    ps_id => 3733,
    ei_id => '464681',
);

$pse_1->add_param('instrument_data_type', 'solexa');
$pse_1->add_param('instrument_data_id', $instrument_data_1->id);
$pse_1->add_param('subject_class_name', 'Genome::Sample');
$pse_1->add_param('subject_id', $sample->id);
$pse_1->add_param('processing_profile_id', $processing_profile->id);
$pse_1->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);

my $instrument_data_2 = Genome::InstrumentData::Solexa->create(
    id => '-101',
    library_id => $library->id,
    flow_cell_id => 'TM-021',
    lane => '2',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);

my $pse_2 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-12346',
    ps_id => 3733,
    ei_id => '464681',
);

$pse_2->add_param('instrument_data_type', 'solexa');
$pse_2->add_param('instrument_data_id', $instrument_data_2->id);
$pse_2->add_param('subject_class_name', 'Genome::Sample');
$pse_2->add_param('subject_id', $sample->id);
$pse_2->add_param('processing_profile_id', $processing_profile->id);
$pse_2->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);

no warnings;
sub GSC::PSE::QueueInstrumentDataForGenomeModeling::get_inherited_assigned_directed_setups_filter_on {
    my $self = shift;
    my $filter = shift;
    my @a;
    push @a, $gsc_workorder if $filter eq 'setup work order';
    push @a, $gsc_project if $filter eq 'setup project';
    return @a;
}

sub GSC::IndexIllumina::get {
    my $self = shift;
    return $ii;
}
use warnings;

my $command_1 = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

isa_ok($command_1, 'Genome::Model::Command::Services::AssignQueuedInstrumentData');
$command_1->dump_status_messages(1);

# Mock copy sequence files pse and its status
my $copy_sequence_pse = Test::MockObject->new;
$copy_sequence_pse->mock('pse_status', sub { 'inprogress' });
$ii->mock('get_copy_sequence_files_pse', sub { $copy_sequence_pse });

ok($command_1->execute(), 'assign-queued-instrument-data executed successfully.');

my $new_models = $command_1->_newly_created_models;
is(scalar(keys %$new_models), 1, 'the cron created one model');
is_deeply([sort map { $_->name } values %$new_models], [sort qw/ AQID-test-sample.prod-refalign /], 'the cron named the new models correctly');

my $models_changed = $command_1->_existing_models_assigned_to;
is(scalar(keys %$models_changed), 0, 'the cron did no work for the second PSE, since the first assigns all on creation');

my $old_models = $command_1->_existing_models_with_existing_assignments;
is(scalar(keys %$old_models), 1, 'the cron found models with data [for the second PSE] already assigned');

my ($old_model_id) = keys(%$old_models);
my $new_model = $new_models->{$old_model_id};
my $old_model = $old_models->{$old_model_id};
is_deeply($new_model, $old_model, 'the model created is the one reused');

ok($new_model->build_requested, 'the cron set the new model to be built');

my @models_for_sample = Genome::Model->get(
    subject_class_name => 'Genome::Sample',
    subject_id => $sample->id,
);
is(scalar(@models_for_sample), 1, 'found one model created for the subject');
is($models_for_sample[0], $new_model, 'that model is the same one the cron claims it created');

my @instrument_data = $new_model->instrument_data;
is(scalar(@instrument_data), 2, 'the first new model has two instrument data assigned');
is_deeply([sort(@instrument_data)], [sort($instrument_data_1, $instrument_data_2)], 'those two instrument data are the ones for our PSEs');

is($pse_1->pse_status, 'completed', 'first pse completed');
is($pse_2->pse_status, 'completed', 'second pse completed');

my ($pse_1_genome_model_id) = $pse_1->added_param('genome_model_id');
my ($pse_2_genome_model_id) = $pse_2->added_param('genome_model_id');

is($pse_1_genome_model_id, $new_model->id, 'genome_model_id parameter set correctly for first pse');
is($pse_2_genome_model_id, $new_model->id, 'genome_model_id parameter set correctly for second pse');

my $group = Genome::ModelGroup->get(name => 'AQID');
ok($group, 'auto-generated model-group exists');

my @members = $group->models;
ok(grep($_ eq $new_model, @members), 'group contains the newly created model');

my $instrument_data_ignored = Genome::InstrumentData::Solexa->create(
    id => '-1101',
    library_id => $library->id,
    flow_cell_id => 'TM-021',
    lane => '2',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
    ignored => 1,
);

my $pse_ignored = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-123456',
    ps_id => 3733,
    ei_id => '464681',
);



$pse_ignored->add_param('instrument_data_type', 'solexa');
$pse_ignored->add_param('instrument_data_id', $instrument_data_2->id);
$pse_ignored->add_param('subject_class_name', 'Genome::Sample');
$pse_ignored->add_param('subject_id', $sample->id);
$pse_ignored->add_param('processing_profile_id', $processing_profile->id);
$pse_ignored->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);


my $command_ignored = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

ok($command_ignored->execute(), 'assign-queued-instrument-data executed successfully.');

my $new_models = $command_ignored->_newly_created_models;
is(scalar(keys %$new_models), 0, 'the cron created no models from ignores.');

# Test AML build 36
my $aml_sample = Genome::Sample->get(name => "H_KA-758168-0912815");
my $aml_library = Genome::Library->create(id => '-1234', sample_id => $aml_sample->id);
isa_ok($aml_sample, 'Genome::Sample');
isa_ok($aml_library, 'Genome::Library');
my $aml_instrument_data = Genome::InstrumentData::Solexa->create(
    id => '-11324234235',
    library_id => $aml_library->id,
    flow_cell_id => 'TM-021',
    lane => '1',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);
ok($aml_instrument_data, 'Created instrument data');
my $aml_pse = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-765431235235',
    ps_id => 3733,
    ei_id => '464681',
);
$aml_pse->add_param('instrument_data_type', 'solexa');
$aml_pse->add_param('instrument_data_id', $aml_instrument_data->id);
$aml_pse->add_param('subject_class_name', 'Genome::Sample');
$aml_pse->add_param('subject_id', $aml_sample->id);
$aml_pse->add_param('processing_profile_id', $processing_profile->id);
$aml_pse->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);
my $aml_command = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

ok($aml_command->execute(), 'assign-queued-instrument-data executed successfully.');
my %aml_new_models = %{$aml_command->_newly_created_models};
for my $model (values(%aml_new_models)) {
    is($model->reference_sequence_build_id, 101947881, 'aml model uses correct reference sequence');
}



# Test MEL build 36
my $aml_sample = Genome::Sample->get(name => "H_KA-758168-0912815");
my $aml_library = Genome::Library->create(id => '-12345', sample_id => $aml_sample->id);
isa_ok($aml_sample, 'Genome::Sample');
isa_ok($aml_library, 'Genome::Library');
my $aml_instrument_data = Genome::InstrumentData::Solexa->create(
    id => '-113242342355',
    library_id => $aml_library->id,
    flow_cell_id => 'TM-021',
    lane => '1',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);
ok($aml_instrument_data, 'Created instrument data');
my $aml_pse = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-7654312352355',
    ps_id => 3733,
    ei_id => '464681',
);
$aml_pse->add_param('instrument_data_type', 'solexa');
$aml_pse->add_param('instrument_data_id', $aml_instrument_data->id);
$aml_pse->add_param('subject_class_name', 'Genome::Sample');
$aml_pse->add_param('subject_id', $aml_sample->id);
$aml_pse->add_param('processing_profile_id', $processing_profile->id);
$aml_pse->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);
my $aml_command = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

ok($aml_command->execute(), 'assign-queued-instrument-data executed successfully.');
my %aml_new_models = %{$aml_command->_newly_created_models};
for my $model (values(%aml_new_models)) {
    is($model->reference_sequence_build_id, 101947881, 'aml model uses correct reference sequence');
}

#Test mouse
my $mouse_taxon = Genome::Taxon->get( species_name => 'mouse' );
my $mouse_individual = Genome::Individual->create(
    id => '-111',
    name => 'AQID-mouse_test-individual',
    common_name => 'AQID_MOUSE_10',
    taxon_id => $mouse_taxon->id,
);

my $mouse_sample = Genome::Sample->create(
    id => '-1111',
    name => 'AQID-mouse_test-sample',
    common_name => 'normal',
    source_id => $mouse_individual->id,
);

my $mouse_library = Genome::Library->create(
    id => '-222',
    sample_id => $mouse_sample->id,
);

isa_ok($mouse_library, 'Genome::Library');
isa_ok($mouse_sample, 'Genome::Sample');

my $mouse_instrument_data = Genome::InstrumentData::Solexa->create(
    id => '-111111',
    library_id => $mouse_library->id,
    flow_cell_id => 'TM-021',
    lane => '1',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);
ok($mouse_instrument_data, 'Created an instrument data');

my $mouse_pse = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-765431',
    ps_id => 3733,
    ei_id => '464681',
);

$mouse_pse->add_param('instrument_data_type', 'solexa');
$mouse_pse->add_param('instrument_data_id', $mouse_instrument_data->id);
$mouse_pse->add_param('subject_class_name', 'Genome::Sample');
$mouse_pse->add_param('subject_id', $mouse_sample->id);
$mouse_pse->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);
my $mouse_command = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

ok($mouse_command->execute(), 'assign-queued-instrument-data executed successfully.');

my %mouse_new_models = %{$mouse_command->_newly_created_models};

is(scalar(keys %mouse_new_models), 1, 'the cron created one model from mouse sample.');
for my $mouse_model_id (keys %mouse_new_models){
    my $mouse_model = $mouse_new_models{$mouse_model_id};
    is($mouse_model->processing_profile_id, '2635769', 'mouse model has the correct procesing profile');
    is($mouse_model->annotation_reference_build_id, '106410073', 'mouse model has the correct annotation build');
    my @mouse_instrument_data = scalar($mouse_model->instrument_data);
    is(scalar(@mouse_instrument_data), 1, "mouse model has the expected 1 instrument data");
}
is($mouse_pse->pse_status, 'completed', 'mouse pse completed');

#Test rna
my $rna_sample = Genome::Sample->create(
    id => '-1001',
    name => 'AQID-rna-test-sample',
    common_name => 'normal',
    source_id => $individual->id,
    extraction_type => 'rna',
);

my $rna_library = Genome::Library->create(
    id => '-2002',
    name => 'rna library',
    sample_id => $rna_sample->id,
);

isa_ok($rna_library, 'Genome::Library');
isa_ok($rna_sample, 'Genome::Sample');

my $rna_instrument_data = Genome::InstrumentData::Solexa->create(
    id => '-100001',
    library_id => $rna_library->id,
    flow_cell_id => 'TM-021',
    lane => '1',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);
ok($rna_instrument_data, 'Created an instrument data');

my $rna_454_instrument_data = Genome::InstrumentData::454->create(
    id => '-14',
    library => $rna_library,
    region_number => 3,
    total_reads => 20,
    run_name => 'R_2010_01_09_11_08_12_FLX08080418_Administrator_100737113',
    sequencing_platform => '454',
);
isa_ok($rna_454_instrument_data, 'Genome::InstrumentData::454');

my $rna_pse = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-765432',
    ps_id => 3733,
    ei_id => '464681',
);

$rna_pse->add_param('instrument_data_type', 'solexa');
$rna_pse->add_param('instrument_data_id', $rna_instrument_data->id);
$rna_pse->add_param('subject_class_name', 'Genome::Sample');
$rna_pse->add_param('subject_id', $rna_sample->id);

my $rna_454_pse = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-12314',
    ps_id => 3733,
    ei_id => '464681',
);

$rna_454_pse->add_param('instrument_data_type', '454');
$rna_454_pse->add_param('instrument_data_id', $rna_454_instrument_data->id);
$rna_454_pse->add_param('subject_class_name', 'Genome::Sample');
$rna_454_pse->add_param('subject_id', $rna_sample->id);

my $rna_command = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

ok($rna_command->execute(), 'assign-queued-instrument-data executed successfully.');

my $rna_new_models = $rna_command->_newly_created_models;
is(scalar(keys %$rna_new_models), 1, 'the cron created 1 rna model');

my $instrument_data_3 = Genome::InstrumentData::Solexa->create(
    id => '-102',
    library_id => $library->id,
    flow_cell_id => 'TM-021',
    lane => '3',
    index_sequence => 'CGTACG',
    subset_name => '3-CGTACG',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);

my $pse_3 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-12347',
    ps_id => 3733,
    ei_id => '464681',
);
$pse_3->add_param('instrument_data_type', 'solexa');
$pse_3->add_param('instrument_data_id', $instrument_data_3->id);
$pse_3->add_param('subject_class_name', 'Genome::Sample');
$pse_3->add_param('subject_id', $sample->id);
$pse_3->add_param('processing_profile_id', $processing_profile->id);
$pse_3->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);

my $fl = Genome::FeatureList->__define__(
    id => 'ABCDEFG',
    name => 'test-capture-data',
    format => 'true-BED',
    content_type => 'targeted',
    reference => $ref_seq_build,
);

my $instrument_data_4 = Genome::InstrumentData::Solexa->create(
    id => '-103',
    library_id => $library->id, 
    flow_cell_id => 'TM-021',
    lane => '3',
    index_sequence => 'ACGTAC',
    subset_name => '3-ACGTAC',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
    target_region_set_name => 'test-capture-data',
);

my $sample_pool = Genome::Sample->create(
    id => '-10001',
    name => 'AQID-test-sample-pooled',
    common_name => 'normal',
    source_id => $individual->id,
);

my $library_pool = Genome::Library->create(
    id => '-10002',
    sample_id => $sample_pool->id,
);

my $instrument_data_pool = Genome::InstrumentData::Solexa->create(
    id => '-1003',
    library_id => $library_pool->id,
    flow_cell_id => 'TM-021',
    lane => '3',
    index_sequence => 'unknown',
    subset_name => '3-unknown',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
    target_region_set_name => 'test-capture-data',
);

my $pse_4 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-12348',
    ps_id => 3733,
    ei_id => '464681',
);
$pse_4->add_param('instrument_data_type', 'solexa');
$pse_4->add_param('instrument_data_id', $instrument_data_4->id);
$pse_4->add_param('subject_class_name', 'Genome::Sample');
$pse_4->add_param('subject_id', $sample->id);
$pse_4->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);

my $command_2 = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

isa_ok($command_2, 'Genome::Model::Command::Services::AssignQueuedInstrumentData');
ok($command_2->execute(), 'assign-queued-instrument-data executed successfully.');

my $new_models_2 = $command_2->_newly_created_models;
is(scalar(keys %$new_models_2), 3, 'the cron created three new models (default, .wu-space, and .tcga-cds)');

my @models = values %$new_models_2;
my @model_groups;
push(@model_groups, $_->model_groups) for (@models);

ok((grep {$_->name eq $sample_pool->name} @model_groups) > 0, "found model_group for sample_pool");
ok((grep {$_->name eq $sample_pool->name . '.wu-space'} @model_groups) > 0, "found wu-space model_group for sample_pool");
ok((grep {$_->name eq $gsc_project->setup_name} @model_groups) > 0, "found model_group for project");
ok((grep {$_->name eq $gsc_project->setup_name . '.wu-space'} @model_groups) > 0, "found wu-space model_group for project");

my $models_changed_2 = $command_2->_existing_models_assigned_to;
is(scalar(keys %$models_changed_2), 1, 'data was assigned to an existing model');

my $old_models_2 = $command_2->_existing_models_with_existing_assignments;
is(scalar(keys %$old_models_2), 1, 'after assigning to existing models found that model again in generic by-sample assignment');

my @new_models_2 = values(%$new_models_2);
my ($model_changed_2) = values(%$models_changed_2);
ok(!grep($_ eq $model_changed_2, @new_models_2), 'the models created are not the one reused');
is($model_changed_2, $new_model, 'the reused model is the one created previously');

for my $m (@new_models_2, $model_changed_2) {
    ok($m->build_requested, 'the cron set the model to be built');
}

my @new_refalign_models = grep($_->name !~ /prod-qc$/, @new_models_2);
is(scalar(@new_refalign_models), 3, 'created three refalign capture models (default, .wu-space, and .tcga-cds)');

for my $m (@new_refalign_models) {

    ok($m->region_of_interest_set_name, 'the new model has a region_of_interest_set_name defined');

    my @instrument_data = $m->instrument_data;
    is(scalar(@instrument_data),1, 'only one instrument data assigned');
    is($instrument_data[0],$instrument_data_4,'the instrument data is the capture data');
}

@models_for_sample = Genome::Model->get(
    subject_class_name => 'Genome::Sample',
    subject_id => $sample->id,
);

is(scalar(@models_for_sample), 4, 'found 4 models created for the subject');

@instrument_data = $new_model->instrument_data;
is(scalar(@instrument_data), 3, 'the new model has three instrument data assigned');
is_deeply([sort(@instrument_data)], [sort($instrument_data_1, $instrument_data_2, $instrument_data_3)], 'those three instrument data are the ones for our PSEs');

is($pse_3->pse_status, 'completed', 'third pse completed');
is($pse_4->pse_status, 'completed', 'fourth pse completed');

my (@pse_3_genome_model_ids) = $pse_3->added_param('genome_model_id');
my (@pse_4_genome_model_ids) = $pse_4->added_param('genome_model_id');

is(scalar(@pse_3_genome_model_ids), 1, 'one genome_model_id parameter for third pse');
is($pse_3_genome_model_ids[0], $new_model->id, 'genome_model_id parameter set correctly for third pse');
is_deeply([sort @pse_4_genome_model_ids], [sort map($_->id, @new_refalign_models)], 'genome_model_id parameter set correctly to match builds created for fourth pse');

my @members_2 = $group->models;
is(scalar(@members_2) - scalar(@members), 3, 'two subsequent models added to the group');

my $instrument_data_5 = Genome::InstrumentData::Solexa->create(
    id => '-104',
    library_id => $library->id,
    flow_cell_id => 'TM-021',
    lane => '5',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);

my $pse_5 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-12349',
    ps_id => 3733,
    ei_id => '464681',
);
$pse_5->add_param('instrument_data_type', 'solexa');
$pse_5->add_param('instrument_data_id', $instrument_data_5->id);
$pse_5->add_param('subject_class_name', 'Genome::Sample');
$pse_5->add_param('subject_id', $sample->id);
$pse_5->add_param('processing_profile_id', $processing_profile->id);

#omitting this to test failure case
#$pse_5->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);

my $de_novo_taxon = Genome::Taxon->get( species_name => 'Zinnia elegans' );

my $de_novo_individual = Genome::Individual->create(
    id => '-11',
    name => 'AQID-test-individual-ze',
    common_name => 'AQID11',
    taxon_id => $taxon->id,
);

my $de_novo_sample = Genome::Sample->create(
    id => '-22',
    name => 'AQID-test-sample-ze',
    common_name => 'normal',
    source_id => $de_novo_individual->id,
);

my $de_novo_library = Genome::Library->create(
    id=>'-33',
    sample_id=>$de_novo_sample->id
);

my $instrument_data_6 = Genome::InstrumentData::Solexa->create(
    id => '-105',
    library_id => $de_novo_library->id,
    flow_cell_id => 'TM-021',
    lane => '6',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);

my $de_novo_processing_profile = Genome::ProcessingProfile::DeNovoAssembly->get(2354215); #apipe-test-de_novo_velvet_solexa

my $pse_6 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-12350',
    ps_id => 3733,
    ei_id => '464681',
);
$pse_6->add_param('instrument_data_type', 'solexa');
$pse_6->add_param('instrument_data_id', $instrument_data_6->id);
$pse_6->add_param('subject_class_name', 'Genome::Sample');
$pse_6->add_param('subject_id', $de_novo_sample->id);
$pse_6->add_param('processing_profile_id', $de_novo_processing_profile->id);

my $command_3 = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

isa_ok($command_3, 'Genome::Model::Command::Services::AssignQueuedInstrumentData');
ok($command_3->execute(), 'assign-queued-instrument-data executed successfully.');

my $new_models_3 = $command_3->_newly_created_models;
is(scalar(keys %$new_models_3), 1, 'the cron created another new model');

my $models_changed_3 = $command_3->_existing_models_assigned_to;
is(scalar(keys %$models_changed_3), 1, 'pse 5 added to existing non-capture model despite pp error');

my $old_models_3 = $command_3->_existing_models_with_existing_assignments;
is(scalar(keys %$old_models_3), 0, 'no other models were found with this data assigned');

my @models_for_de_novo_sample = Genome::Model->get(
    subject_class_name => 'Genome::Sample',
    subject_id => $de_novo_sample->id,
);
is(scalar(@models_for_de_novo_sample), 1, 'found 1 models created for the de-novo subject');

my($new_de_novo_model) = values %$new_models_3;
ok($new_de_novo_model->build_requested, 'the cron set the new model to be built');
my @de_novo_instrument_data = $new_de_novo_model->instrument_data;
is(scalar(@de_novo_instrument_data), 1, 'the new model has one instrument data assigned');
is($de_novo_instrument_data[0], $instrument_data_6, 'is the expected instrument data');

my($changed_model_3) = values %$models_changed_3;
is($changed_model_3, $new_model, 'latest addition is to the original model from the first run');

is($pse_5->pse_status, 'inprogress', 'fifth pse inprogress (due to incomplete information)');
is($pse_6->pse_status, 'completed', 'sixth pse completed');

my ($pse_5_genome_model_id) = $pse_5->added_param('genome_model_id');
my ($pse_6_genome_model_id) = $pse_6->added_param('genome_model_id');

is($pse_5_genome_model_id, undef, 'genome_model_id parameter remains unset on fifth pse');
is($pse_6_genome_model_id, $new_de_novo_model->id, 'genome_model_id parameter set correctly for sixth pse');

##Cleanup failure case from previous test
$pse_5 = undef;
$instrument_data_5->delete;
##

my $sample_2 = Genome::Sample->create(
    id => '-70',
    name => 'TCGA-TEST-SAMPLE-01A-01D',
    common_name => 'normal',
    source_id => $individual->id,
    extraction_label => 'TCGA-Test',
);
ok($sample_2, 'Created TCGA sample');

my $sample_3 = Genome::Sample->create(
    id => '-71',
    name => 'TCGA-TEST-SAMPLE-10A-01D',
    common_name => 'normal',
    source_id => $individual->id,
    extraction_label => 'TCGA-Test',
);
ok($sample_3, 'Created TCGA sample pair');

my $library_2 = Genome::Library->create(
    id => '-7',
    sample_id => $sample_2->id,
);
isa_ok($library_2, 'Genome::Library');

my $instrument_data_7 = Genome::InstrumentData::Solexa->create(
    id => '-700',
    library_id => $library_2->id,
    flow_cell_id => 'TM-021',
    lane => '1',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
    target_region_set_name => 'BRC10 capture chip set',
);
ok($instrument_data_7, 'Created an instrument data');

my $pse_7 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-7675309',
    ps_id => 3733,
    ei_id => '464681',
);

$pse_7->add_param('instrument_data_type', 'solexa');
$pse_7->add_param('instrument_data_id', $instrument_data_7->id);
$pse_7->add_param('subject_class_name', 'Genome::Sample');
$pse_7->add_param('subject_id', $sample_2->id);
$pse_7->add_param('processing_profile_id', $processing_profile->id);
$pse_7->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);

my $command_4 = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

isa_ok($command_4, 'Genome::Model::Command::Services::AssignQueuedInstrumentData');
ok($command_4->execute(), 'assign-queued-instrument-data executed successfully.');

my $new_models_4 = $command_4->_newly_created_models;
is(scalar(keys %$new_models_4), 5, 'the cron created five new models');
my ($somatic_variation) =  grep($_->isa("Genome::Model::SomaticVariation"), values %$new_models_4);
my @tumor = grep($_->subject_name eq  $sample_2->name, values %$new_models_4);
my ($normal) = grep($_->subject_name eq  $sample_3->name, values %$new_models_4);
ok($somatic_variation, 'the cron created a somatic variation model');
ok(@tumor, 'the cron created a tumor model for the first sample');
ok($normal, 'the cron created a paired normal model');
ok(grep($_ ==  $somatic_variation->tumor_model, @tumor), 'somatic variation has the correct tumor model');
is($normal, $somatic_variation->normal_model, 'somatic variation has the correct normal model');
is(scalar @{[$normal->instrument_data]}, 0, 'no instrument data is assigned to the normal');
is($normal->build_requested, 0, 'the normal model does not have a build requested since no instrument data is assigned to it');

@models = values %$new_models_4;
push(@model_groups, $_->model_groups) for (@models);
ok((grep {$_->name =~ /\.tcga/} @model_groups), "found tcga-cds model_group");

is($pse_7->pse_status, 'completed', 'seventh pse completed');

my $library_3 = Genome::Library->create(
    id => '-9',
    sample_id => $sample_3->id,
);
isa_ok($library_3, 'Genome::Library');

my $instrument_data_8 = Genome::InstrumentData::Solexa->create(
    id => '-777',
    library_id => $library_3->id,
    flow_cell_id => 'TM-021',
    lane => '1',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
    target_region_set_name => 'BRC10 capture chip set',
);
ok($instrument_data_8, 'Created an instrument data');

my $pse_8 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-7775309',
    ps_id => 3733,
    ei_id => '464681',
);

$pse_8->add_param('instrument_data_type', 'solexa');
$pse_8->add_param('instrument_data_id', $instrument_data_8->id);
$pse_8->add_param('subject_class_name', 'Genome::Sample');
$pse_8->add_param('subject_id', $sample_3->id);
$pse_8->add_param('processing_profile_id', $processing_profile->id);
$pse_8->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);


my $command_5 = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);


isa_ok($command_5, 'Genome::Model::Command::Services::AssignQueuedInstrumentData');
ok($command_5->execute(), 'assign-queued-instrument-data executed successfully.');
my $new_models_5 = $command_5->_newly_created_models;
is(scalar(keys %$new_models_5), 0, 'the cron created zero new models');
ok(scalar($normal->instrument_data), 'the cron assigned the new instrument data to the empty paired model');

###
my $sample_4 = Genome::Sample->create(
    id => '-80',
    name => 'TCGA-TEST-SAMPLE2-01A-01D',
    common_name => 'normal',
    source_id => $individual->id,
    extraction_label => 'TCGA-Test',
);
ok($sample_4, 'Created TCGA sample');

my $sample_5 = Genome::Sample->create(
    id => '-81',
    name => 'TCGA-TEST-SAMPLE2-10A-01D',
    common_name => 'normal',
    source_id => $individual->id,
    extraction_label => 'TCGA-Test',
);
ok($sample_5, 'Created TCGA sample pair');

my $library_4 = Genome::Library->create(
    id => '-11',
    sample_id => $sample_4->id,
);
isa_ok($library_4, 'Genome::Library');

my $library_5 = Genome::Library->create(
    id => '-10',
    sample_id => $sample_5->id,
);
isa_ok($library_5, 'Genome::Library');

my $instrument_data_9 = Genome::InstrumentData::Solexa->create(
    id => '-800',
    library_id => $library_4->id,
    flow_cell_id => 'TM-021',
    lane => '1',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);
ok($instrument_data_9, 'Created an instrument data');

my $instrument_data_10 = Genome::InstrumentData::Solexa->create(
    id => '-801',
    library_id => $library_5->id,
    flow_cell_id => 'TM-021',
    lane => '1',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 65535,
    rev_clusters => 65536,
);
ok($instrument_data_10, 'Created an instrument data');

my $pse_9 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-7600000',
    ps_id => 3733,
    ei_id => '464681',
);
$pse_9->add_param('instrument_data_type', 'solexa');
$pse_9->add_param('instrument_data_id', $instrument_data_9->id);
$pse_9->add_param('subject_class_name', 'Genome::Sample');
$pse_9->add_param('subject_id', $sample_4->id);
$pse_9->add_param('processing_profile_id', $processing_profile->id);
$pse_9->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);

my $pse_10 = GSC::PSE::QueueInstrumentDataForGenomeModeling->create(
    pse_status => 'inprogress',
    pse_id => '-7600001',
    ps_id => 3733,
    ei_id => '464681',
);
$pse_10->add_param('instrument_data_type', 'solexa');
$pse_10->add_param('instrument_data_id', $instrument_data_10->id);
$pse_10->add_param('subject_class_name', 'Genome::Sample');
$pse_10->add_param('subject_id', $sample_5->id);
$pse_10->add_param('processing_profile_id', $processing_profile->id);
$pse_10->add_reference_sequence_build_param_for_processing_profile( $processing_profile, $ref_seq_build);

my $command_6 = Genome::Model::Command::Services::AssignQueuedInstrumentData->create(
    test => 1,
);

isa_ok($command_6, 'Genome::Model::Command::Services::AssignQueuedInstrumentData');
ok($command_6->execute(), 'assign-queued-instrument-data executed successfully.');

my $new_models_6 = $command_6->_newly_created_models;
is(scalar(keys %$new_models_6), 3, 'the cron created three new models');
my ($somatic_variation_2) =  grep($_->isa("Genome::Model::SomaticVariation"), values %$new_models_6);
my @tumor_2 = grep($_->subject_name eq  $sample_4->name, values %$new_models_6);
my ($normal_2) = grep($_->subject_name eq  $sample_5->name, values %$new_models_6);
ok($somatic_variation_2, 'the cron created a somatic variation model');
ok(@tumor_2, 'the cron created a tumor model for the first sample');
ok($normal_2, 'the cron created a paired normal model');
ok(grep($_ ==  $somatic_variation_2->tumor_model, @tumor_2), 'somatic variation has the correct tumor model');
is($normal_2, $somatic_variation_2->normal_model, 'somatic variation has the correct normal model');
is(scalar @{[$normal_2->instrument_data]}, 1, 'one instrument data is assigned to the normal');
is($normal->build_requested, 1, 'the normal model has build requested since there is instrument data is assigned to it');
