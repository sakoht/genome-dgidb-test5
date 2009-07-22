#!/gsc/bin/perl

use strict;
use warnings;

use Test::More tests => 9;

use above 'Genome';

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    require_ok('Genome::Model::Command::Build::Run');
};

my $tmp_dir = File::Temp::tempdir('RunJobsXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);

my @stages = qw( stage1 ); #stage2 stage3  stage4);
my @mock_instrument_data = map { Genome::InstrumentData->create_mock(
                                                                     id => UR::DataSource->next_dummy_autogenerated_id,
                                                                     sequencing_platform => 'mock',
                                                                     sample_name => $_,
                                                                 ) } (1 .. 4);
my @subreferences = qw(1 .. 10);

my $mock_pp = Genome::ProcessingProfile->create_mock(
                                                     id => UR::DataSource->next_dummy_autogenerated_id,
                                                     type_name => 'run jobs test',
                                                 );
isa_ok($mock_pp,'Genome::ProcessingProfile');
$mock_pp->set_list('stages',@stages);

my $model_id = UR::DataSource->next_dummy_autogenerated_id;
my $mock_model = Genome::Model->create_mock(
                                            id => $model_id,
                                            genome_model_id => $model_id,
                                            name => 'run_jobs_model',
                                            subject_type => 'run_jobs_subject_type',
                                            subject_name => 'run_jobs_subject_name',
                                            processing_profile_id => $mock_pp->id,
                                            data_directory => $tmp_dir .'/model_data_dir',
                                        );
isa_ok($mock_model,'Genome::Model');

my $build_id = UR::DataSource->next_dummy_autogenerated_id;
my $mock_build = Genome::Model::Build->create_mock(
                                              id => $build_id,
                                              build_id => $build_id,
                                              model_id => $mock_model->id,
                                              data_directory => $mock_model->data_directory .'/build'. $build_id,
                                          );
isa_ok($mock_build,'Genome::Model::Build');

my $build_event_id = UR::DataSource->next_dummy_autogenerated_id;
my $mock_build_event = Genome::Model::Command::Build->create_mock(
                                                                  id => $build_event_id,
                                                                  genome_model_event_id => $build_event_id,
                                                                  model_id => $mock_model->id,
                                                                  event_type => 'genome model build',
                                                              );
isa_ok($mock_build_event,'Genome::Model::Command::Build');

my @stage1_events;
for my $mock_instrument_data (@mock_instrument_data) {
    my $prior_event;
    for (1 .. 3) {
        my $mock_event_id = UR::DataSource->next_dummy_autogenerated_id;
        my $mock_event = Genome::Model::Event->create_mock(
                                                           id => $mock_event_id,
                                                           genome_model_event_id => $mock_event_id,
                                                           model_id => $mock_model->id,
                                                           instrument_data_id => $mock_instrument_data->id,
                                                           event_type => 'mock_run_jobs_event_'. $_,
                                                       );
        $mock_event->set_always('resolve_log_directory',$mock_build->data_directory .'/'. $mock_event_id);
        $mock_event->set_always('bsub_rusage','mock_bsub_rusage');
        $mock_event->set_always('command_name_brief',$mock_event->event_type);
        $mock_event->mock('create_directory',\&Genome::Utility::FileSystem::create_directory);
        $mock_event->mock('execute',sub { return 1; });
        $mock_event->set_list('next_events',);
        if ($prior_event) {
            $mock_event->set_always('prior_event_id',$prior_event->id);
            $prior_event->set_list('next_events',$mock_event);
        } else {
            $mock_event->set_always('prior_event_id',undef);
        }
        push @stage1_events, $mock_event;
        $prior_event = $mock_event;
    }
}
$mock_build_event->mock('events_for_stage', sub {
                            my $self = shift;
                            my $stage_name = shift;
                            if ($stage_name eq 'stage1') {
                                return @stage1_events;
                            } elsif ($stage_name eq 'stage2') {

                            } elsif ($stage_name eq 'stage3') {

                            } elsif ($stage_name eq 'stage4') {

                            }
                        }
                    );

$mock_build->set_always('build_event',$mock_build_event);

ok(Genome::Utility::FileSystem->create_directory($mock_build->data_directory),'created build data directory '. $mock_build->data_directory);

# run is just a wrapper around a workflow engine, we can make it run any xml as an adequite test for now

{

    my $w = Workflow::Model->create(
        name => 'container',
        input_properties => [ 'prior_result'],
        output_properties => [ 'result' ]
    );
    
    my $i = $w->get_input_connector;
    my $o = $w->get_output_connector;
        
    $w->add_link(
        left_operation => $i,
        left_property => 'prior_result',
        right_operation => $o,
        right_property => 'result'
    );
    
    $w->save_to_xml(OutputFile => $mock_build->data_directory . '/build.xml');

}

my $xml_file = $mock_build->data_directory.'/build.xml';
ok(-f $xml_file, "xml file '$xml_file' exists");

my $run_job =  Genome::Model::Command::Build::Run->create(
    build_id => $mock_build->id,
    model_id => $mock_model->id
);

isa_ok($run_job,'Genome::Model::Command::Build::Run');

ok($run_job->execute,'execute the command '. $run_job->command_name);

