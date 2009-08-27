#!/gsc/bin/perl

use strict;
use warnings;

use Data::Dumper;
use above "Genome";
#use Test::More tests => 244;
use Test::More 'no_plan';

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

ok(my $define = Genome::Model::Command::Define::Somatic->create(
        tumor_model_id => '2793277373',
        normal_model_id => '2793278677',
        data_directory => '/gscmnt/sata820/info/medseq/somatic_pipeline/ovc1-test-somatic-models',
        subject_name => 'amlsomething_somatic',
        model_name => 'somatic_test')
    , "created define command");
isa_ok($define, "Genome::Model::Command::Define::Somatic");
ok($define->execute, "executed define command");

ok(my $model_id = $define->result_model_id, "Got result model id");
ok(my $model = Genome::Model->get($model_id), "Got the model from result model id");
isa_ok($model, "Genome::Model::Somatic");

ok(my $build = Genome::Model::Command::Build->create(
        model_id => $model->genome_model_id), "created build command");
