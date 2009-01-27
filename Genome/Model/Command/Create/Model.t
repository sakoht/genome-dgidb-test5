#!/gsc/bin/perl

# This test confirms the ability to create a processing profile and then create
# a genome model using that processing profile

use strict;
use warnings;

use Data::Dumper;
use above "Genome";
use Command;
use Test::More tests => 160;
use Test::Differences;
use File::Path;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

my $default_subject_name = 'H_GV-933124G-skin1-9017g';
my $default_subject_type = 'sample_name';
my $default_pp_name = 'solexa_maq0_6_8';

is(Genome::Model::Command::Create::Model->help_brief,'create a new genome model','help_brief test');
like(Genome::Model::Command::Create::Model->help_synopsis, qr(^genome-model create),'help_synopsis test');
like(Genome::Model::Command::Create::Model->help_detail,qr(^This defines a new genome model),'help_detail test');
# test normal model and processing profile creation for reference alignment
test_model_from_params(
                       model_params => {
                                        subject_name            => $default_subject_name,
                                        subject_type            => $default_subject_type,
                                        processing_profile_name => $default_pp_name,
                                    },
                   );

# test create for a genome model with defined model_name
test_model_from_params(
                       model_params => {
                                        model_name              => "test_model_$ENV{USER}",
                                        subject_name            => $default_subject_name,
                                        subject_type            => $default_subject_type,
                                        processing_profile_name => $default_pp_name,
                                    },
                   );
# test create for a genome model with an incorrect subject_type
test_model_from_params(
                       test_params => {
                                       fail => 'invalid_subject_type',
                                   },
                       model_params => {
                                        subject_name => $default_subject_name,
                                        subject_type => 'invalid_subject_type',
                                        processing_profile_name   => $default_pp_name,
                                    },
                   );
# test create for a genome model with an incorrect subject_name
test_model_from_params(
                       test_params => {
                                       fail => 'invalid_subject_name',
                                   },
                       model_params => {
                                        subject_name => 'invalid_subject_name',
                                        subject_type => $default_subject_type,
                                        processing_profile_name   => $default_pp_name,
                                    },
                   );
# test create for a genome model with an incorrect subject_name
test_model_from_params(
                       test_params => {
                                       fail => 'invalid_pp_name',
                                   },
                       model_params => {
                                        subject_name => $default_subject_name,
                                        subject_type => $default_subject_type,
                                        processing_profile_name   => 'invalid_pp_name',
                                    },
                   );
# test when no processing profile name passed as arg
test_model_from_params(
                       test_params => {
                                       fail => 'No value specified for required property processing_profile_name',
                                   },
                       model_params => {
                                        subject_name => $default_subject_name,
                                        subject_type => $default_subject_type,
                                    },
                   );
# test when no subject name is passed as arg
test_model_from_params(
                       test_params => {
                                       fail => 'No value specified for required property subject_name',
                                   },
                       model_params => {
                                        subject_type => $default_subject_type,
                                        processing_profile_name   => $default_pp_name,
                                    },
                   );

# test when bare args empty array_ref is passed
test_model_from_params(
                       model_params => {
                                        subject_name => $default_subject_name,
                                        subject_type => $default_subject_type,
                                        processing_profile_name   => $default_pp_name,
                                        bare_args => [],
                                    },
                   );

# test when a bogus_param gets passed in as bare args
test_model_from_params(
                       test_params => {
                                       fail => 'bogus_param',
                                   },
                       model_params => {
                                        subject_name => $default_subject_name,
                                        subject_type => $default_subject_type,
                                        processing_profile_name   => $default_pp_name,
                                        bare_args => [ 'bogus_param' ],
                                    },
                   );

# test create for a genome model micro array illumina
test_model_from_params(
                       model_params => {
                                        subject_name => $default_subject_name,
                                        subject_type => $default_subject_type,
                                        processing_profile_name   => 'micro-array-illumina',
                                    },
                   );
# test create for a genome model micro array illumina
test_model_from_params(
                       model_params => {
                                        subject_name => $default_subject_name,
                                        subject_type => $default_subject_type,
                                        processing_profile_name   => 'micro-array-affymetrix',
                                    },
                   );
# test create for a genome model assembly
test_model_from_params(
                       model_params => {
                                        subject_name => $default_subject_name,
                                        subject_type => $default_subject_type,
                                        processing_profile_name   => '454_newbler_default_assembly',
                                    },
                   );
exit;

sub test_model_from_params {
    my %params = @_;
    my %test_params = %{$params{'test_params'}} if defined $params{'test_params'};

    my %model_params = %{$params{'model_params'}};
    if ($test_params{'fail'}) {
        &failed_create_model($test_params{'fail'},\%model_params);
    } else {
        &successful_create_model(\%model_params);
    }
}


sub successful_create_model {
    my $params = shift;
    my %params = %{$params};

    my $pp = Genome::ProcessingProfile->get(name => $params{processing_profile_name});
    isa_ok($pp,'Genome::ProcessingProfile');

    my $subclass = join('', map { ucfirst($_) } split('\s+',$pp->type_name));
    if ($params{'model_name'}) {
        my $test_model_link_pathname = Genome::Model->model_links_directory . '/' . $params{'model_name'};
        symlink('/tmp/', $test_model_link_pathname);
    }

    if (!$params{subject_name}) {
        $params{subject_name} = 'invalid_subject_name';
    }

    my $create_command = Genome::Model::Command::Create::Model->create(%params);
    isa_ok($create_command,'Genome::Model::Command::Create::Model');

    $create_command->dump_error_messages(0);
    $create_command->dump_warning_messages(0);
    $create_command->dump_status_messages(0);
    $create_command->queue_error_messages(1);
    $create_command->queue_warning_messages(1);
    $create_command->queue_status_messages(1);

    ok($create_command->execute, 'create command execution successful');
    my @error_messages = $create_command->error_messages();
    my @warning_messages = $create_command->warning_messages();
    my @status_messages = $create_command->status_messages();
    ok(! scalar(@error_messages), 'no error messages');
    if ($params{'model_name'}) {
        ok(scalar(@warning_messages), 'create model generated a warning message');
        like($warning_messages[0], qr(model symlink.*already exists), 'Warning message complains about the model link already existing');
    } else {
        ok(!scalar(@warning_messages), 'no warning messages');
        if (@warning_messages) {
            print join("\n",@warning_messages);
        }
    }
    ok(scalar(@status_messages), 'There was a status message');

    unless ($params{'model_name'}) {
        my $subject_name = Genome::Model::Command::Create::Model->_sanitize_string_for_filesystem($params{subject_name});
        $params{'model_name'} = $subject_name .'.'. $params{processing_profile_name};
    }

    is($status_messages[0], "created model $params{'model_name'}", 'First message is correct');
    # FIXME - some of those have a second message about creating a directory
    # should probably test for that too

    my $model_name = delete($params{model_name});
    delete($params{bare_args});
    my $model = Genome::Model->get(name => $model_name,);
    isa_ok($model,'Genome::Model::'. $subclass);
    ok($model, 'creation worked for '. $model_name .' model');
    is($model->name,$model_name,'model model_name accessor');
    for my $property_name (keys %params) {
        is($model->$property_name,$params{$property_name},$property_name .' model indirect accessor');
    }

    is($model->processing_profile_id,$pp->id,'model processing_profile_id indirect accessor');
    is($model->type_name,$pp->type_name,'model type_name indirect accessor');
    for my $param ($pp->params) {
        my $accessor = $param->name;
        is($model->$accessor,$param->value,$accessor .' model indirect accessor');
    }

  SKIP: {
        skip 'no model to delete', 2 unless $model;
        # This would normally emit a warning message about deleting the create command object
        # but in the process of deleting the model it will also delete the command object,
        # leaving us no way to get the warning messages back.  Punt and just ignore them...
        delete_model($model);
    }
}


sub failed_create_model {
    my $reason = shift;
    my $params = shift;
    my %params = %{$params};
    my  $create_command = Genome::Model::Command::Create::Model->create(%params);
    isa_ok($create_command,'Genome::Model::Command::Create::Model');

    $create_command->dump_error_messages(0);
    $create_command->dump_warning_messages(0);
    $create_command->dump_status_messages(0);
    $create_command->dump_usage_messages(0);
    $create_command->queue_error_messages(1);
    $create_command->queue_warning_messages(1);
    $create_command->queue_status_messages(1);
    ok(!$create_command->execute, 'create command execution failed');
    my @error_messages = $create_command->error_messages();
    my @warning_messages = $create_command->warning_messages();
    my @status_messages = $create_command->status_messages();
    ok(scalar(@error_messages), 'There are error messages');
    like($error_messages[0], qr($reason), 'Error message about '. $reason);
    ok(!scalar(@warning_messages), 'no warning message');
    ok(!scalar(@status_messages), 'no status message');
}

sub delete_model {
    my $model = shift;
    ok($model->delete,'delete model');
}

1;
