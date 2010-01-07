#!/gsc/bin/perl

# FIXME Tests to cover:
# Allocation - all allocation in builds are not tested
# Reports - limited report testing

use strict;
use warnings;

use above 'Genome';

use Test::More 'no_plan';
require Genome::Model::Test;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    use_ok('Genome::Model::Build');
}

#< Mock Model >#
my $model = Genome::Model::Test->create_basic_mock_model(
    type_name => 'tester',
);
ok($model, 'Create mock model');
my $inst_data = Genome::InstrumentData->get('2sep09.934pmaa1');
ok( # create ida like this, so it doesn't go thru creat of the ida class, which copies it as an input.  Now we can see if previously assigned inst data will be copied into a builds inputs
    Genome::Model::Test->create_mock_instrument_data_assignments($model, $inst_data),
    'Create mock inst data assn',
);
my @model_inst_data = $model->instrument_data;
ok(@model_inst_data, 'Added instrument data to model');
$model->coolness('moderate'); 
my @model_inputs = $model->inputs;
is(scalar(@model_inputs), 1, 'Correct number of model inputs'); # should be 2, one for coolness, one for the inst data creatd in assignment

#< Real create >#
my $build = Genome::Model::Build->create(
    model_id => $model->id,
);
ok($build, 'Created build');
isa_ok($build, 'Genome::Model::Build');
is($build->data_directory,$model->data_directory.'/build'. $build->id, 'build directory resolved');
is($build->model->id, $model->id, 'indirect model accessor');

#< Inputs - Inst Data and Coolness >#
my @build_inputs = $build->inputs;
is(scalar(@build_inputs), 2, 'Correct number of build inputs');
my @build_inst_data = $build->instrument_data;
is_deeply(\@build_inst_data, [ $inst_data ], 'Build instrument data');
is($build->coolness, 'moderate', 'Got coolness'); 
#print Data::Dumper::Dumper({bin=>\@build_inputs,bid=>\@build_inst_data,min=>\@model_inputs,mid=>\@model_inst_data,});

#< ACTIONS >#
# SCHEDULE
# try to init, succ and fail an unscheduled build
ok(!$build->initialize, 'Failed to initialize an unscheduled build');
ok(!$build->fail, 'Failed to fail an unscheduled build');
ok(!$build->success, 'Failed to success an unscheduled build');
# schedule - check events
my $stages = $build->schedule;
ok($stages, 'Scheduled build');
is_deeply(
    [ map { $_->{name} } @$stages ],
    [qw/ prepare assemble /],
    'Got scheduled stage names',
);
is_deeply(
    [ map { scalar(@{$_->{events}}) } @$stages ],
    [qw/ 1 3 /],
    'Got scheduled stage events',
);
my $build_event = $build->build_event;
ok($build_event, 'Got build event');
is($build_event->event_status, 'Scheduled', 'Build status is Scheduled');
is($build->build_status, 'Scheduled', 'Build status is Scheduled');
my @events = Genome::Model::Event->get(
    id => { operator => 'ne', value => $build_event->id },
    model_id => $model->id,
    build_id => $build->id,
    event_status => 'Scheduled',
);
is(scalar(@events), 4, 'Scheduled 4 events');
# try to schedule again - should fail
ok(!$build->schedule, 'Failed to schedule build again');

# do not send the report
my $gss_report = *Genome::Model::Build::generate_send_and_save_report;
no warnings 'redefine';
*Genome::Model::Build::generate_send_and_save_report = sub{ return 1; };
use warnings;

# INITIALIZE
ok($build->initialize, 'Initialize');
is($build->build_status, 'Running', 'Status is Running');
is($model->current_running_build_id, $build->id, 'Current running build id set to build id in initialize');

# FAIL
ok($build->fail([]), 'Fail');
is($build->build_status, 'Failed', 'Status is Failed');

# SUCCESS
ok($build->success, 'Success');
is($build->build_status, 'Succeeded', 'Status is Succeeded');
ok(!$model->current_running_build_id, 'Current running build id set to undef in success');
is($model->last_complete_build_id, $build->id, 'Last complete build id set to build id in success');

# ABANDON
ok($build->abandon, 'Abandon');
is($build->build_status, 'Abandoned', 'Status is Abandoned');
is(grep({$_->event_status eq 'Abandoned'} @events), 4, 'Abandoned all events');
# try to init, fail and succeed a abandoned build
ok(!$build->initialize, 'Failed to initialize an abandoned build');
ok(!$build->fail, 'Failed to fail an abandoned build');
ok(!$build->success, 'Failed to success an abandoned build');

no warnings 'redefine';
*Genome::Model::Build::generate_send_and_save_report = $gss_report;
use warnings;

#< Reports >#
# to addressees
is(
    $build->_get_to_addressees_for_report_generator_class('Genome::Model::Report::BuildInitialized'),
    $ENV{USER}.'@genome.wustl.edu', 
    "reports go to $ENV{USER}",
);
$build->build_event->user_name('apipe'); # check for apipe
is(
    $build->_get_to_addressees_for_report_generator_class('Genome::Model::Report::BuildInitialized'),
    'apipe-run@genome.wustl.edu', 
    'apipe\'s reports go to apipe-run',
);
is(
    $build->_get_to_addressees_for_report_generator_class('Genome::Model::Report::BuildFailed'),
    'apipe-bulk@genome.wustl.edu', 
    'apipe\'s failed reports go to apipe-bulk',
);

exit;

#$HeadURL$
#$Id$
