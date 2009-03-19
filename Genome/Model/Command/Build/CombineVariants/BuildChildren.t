#!/gsc/bin/perl

use strict;
use warnings;
use above "Genome";
use Test::More tests => 6;
use File::Path;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

use_ok ('Genome::Model::Command::Build::CombineVariants::BuildChildren');
my $test_dir = File::Temp::tempdir('CombineVariantsTestXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);

# TODO: replace this model and build with mock objects or something better... but for now...
my $genes = 'EGFR,KIT';
my $pp = Genome::ProcessingProfile::CombineVariants->create(name => "test-combine-variants", limit_genes_to => $genes);
ok ($pp, "Created test processing profile"); 
my $model = Genome::Model::CombineVariants->create(processing_profile_id => $pp->id, subject_type => 'sample_group', data_directory => $test_dir);
ok ($model, "Created test model");

ok(my $dump = Genome::Model::Command::Build::CombineVariants::BuildChildren->create
    (model_id => $model->id), 'Created BuildChildren object');
isa_ok($dump, 'Genome::Model::Command::Build::CombineVariants::BuildChildren'); 
ok (-e $model->data_directory, "data dir " . $model->data_directory ."exists");

#TODO how do we test this better?
