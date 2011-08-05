#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

use_ok('Genome::Model');

my $individual = Genome::Individual->create(
    name => 'test individual',
);
ok($individual, 'created test individual') or die;

my $sample = Genome::Sample->create(
    name => 'test sample',
    source_id => $individual->id,
);
ok($sample, 'created test sample') or die;

my $library = Genome::Library->create(
    name => 'test library',
    sample_id => $sample->id,
);
ok($library, 'created test library') or die;
class Genome::ProcessingProfile::Test {
    is => 'Genome::ProcessingProfile'
};

my $pp = Genome::ProcessingProfile::Test->create(name => 'test pp');
ok($pp, 'created test processing profile') or die;

my $model = Genome::Model::Test->create(
    subject_id => $sample->id,
    subject_class_name => $sample->class,
    processing_profile_id => $pp->id,
);
ok($model, 'created test model') or die;

######

my $inst_data = Genome::InstrumentData::Solexa->create(library_id => $library->id);
ok($inst_data, 'created test instrument data') or die;

$model->add_instrument_data($inst_data);

my $rule = $model->create_rule_limiting_instrument_data;
isa_ok($rule, 'UR::BoolExpr');

my %rule_params = $rule->params_list;
ok(exists $rule_params{'library_id'}, 'library id exists in rule parameters');
ok($rule_params{'library_id'} eq $inst_data->library_id, 'rule contains expected library id value');

######

my $library2 = Genome::Library->create(
    name => 'another test library',
    sample_id => $sample->id,
);
ok($library2, 'created another test library') or die;

my $inst_data2 = Genome::InstrumentData::Solexa->create(library_id => $library2->id);
ok($inst_data2, 'created test instrument data using new library') or die;

$model->add_instrument_data($inst_data2);

my $rule2 = $model->create_rule_limiting_instrument_data;
isa_ok($rule2, 'UR::BoolExpr');

my %rule2_params = $rule2->params_list;
ok(exists $rule2_params{'sample_id'}, 'sample id exists in rule parameters');
ok($rule2_params{'sample_id'} eq $inst_data2->sample_id, 'sample id in rule matches that in instrument data');

######

my $sample3 = Genome::Sample->create(
    name => 'another test sample',
    source_id => $individual->id,
);
ok($sample3, 'made another test sample') or die;

my $library3 = Genome::Library->create(
    sample_id => $sample3->id,
    name => 'yet another test library',
);
ok($library3, 'made another test library') or die;

my $inst_data3 = Genome::InstrumentData::Solexa->create(library_id => $library3->id);
ok($inst_data3, 'made another test instrument data') or die;

$model->add_instrument_data($inst_data3);

my $rule3 = $model->create_rule_limiting_instrument_data;
isa_ok($rule3, 'UR::BoolExpr');

my %rule3_params = $rule3->params_list;
ok(exists $rule3_params{'sample_source_id'}, 'sample source id in rule parameters');
ok($rule3_params{'sample_source_id'} eq $inst_data3->sample_source_id, 'sample source id in rule matches that in instrument data');

done_testing();


