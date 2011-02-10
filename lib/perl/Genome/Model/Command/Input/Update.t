#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';

use Data::Dumper 'Dumper';
require File::Temp;
require Genome::Model::Test;
use Test::More;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

use_ok('Genome::Model::Command::Input::Update') or die;

my $model = Genome::Model->get(2857912274); # apipe-test-05-de_novo_velvet_solexa
ok($model, 'got model') or die;

my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
my $build = Genome::Model::Build->create( # make sure we don't abandon builds
    model => $model,
    data_directory => $tmpdir,
);
ok($build, 'create build');
is_deeply([$build->instrument_data], [$model->instrument_data], 'copied instrument data');
my $master_event = Genome::Model::Event->create(
    event_type => 'genome model build',
    event_status => 'Succeeded',
    model => $model,
    build => $build,
    user_name => $ENV{USER},
    date_scheduled => UR::Time->now,
    date_completed => UR::Time->now,
);
ok($master_event, 'created master event');
is_deeply($build->the_master_event, $master_event, 'got master event from build');

my $update = Genome::Model::Command::Input::Update->create(
    model => $model,
    name => 'center_name',
    value => 'Baylor',
);
ok($update, 'create');
$update->dump_status_messages(1);
ok($update->execute, 'execute');
is($build->status, 'Succeeded', 'build is Succeeded') or die;

note('Update to undef');
$update = Genome::Model::Command::Input::Update->create(
    model => $model,
    name => 'center_name',
    value => '',
);
ok($update, 'create');
$update->dump_status_messages(1);
ok($update->execute, 'execute');
is($build->status, 'Succeeded', 'build is Succeeded') or die;

note('Try to use update for is_many property');
$update = Genome::Model::Command::Input::Update->create(
    model => $model,
    name => 'instrument_data',
    value => 'Watson',
);
ok($update, 'create');
$update->dump_status_messages(1);
ok(!$update->execute, 'execute');
is($build->status, 'Succeeded', 'build is Succeeded') or die;

done_testing();
exit;

