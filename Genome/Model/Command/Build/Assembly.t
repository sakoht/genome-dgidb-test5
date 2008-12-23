#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use Test::More;
use File::Path;

use Data::Dumper;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

my $turn_on_messages = 0;

BEGIN {
    my $archos = `uname -a`;
    if ($archos !~ /64/) {
        plan skip_all => "Must run from 64-bit machine";
    }
    plan tests => 201;

    use_ok( 'Genome::RunChunk::454');
    use_ok( 'Genome::Model::Assembly');
    use_ok( 'Genome::ProcessingProfile::Assembly');
    use_ok( 'Genome::Model::Command::Define' );
    use_ok( 'Genome::ProcessingProfile::Command::Create' );
    use_ok( 'Genome::Model::Command::Build::Assembly' );
    use_ok( 'Genome::Model::Command::Build::Assembly::AssignReadSetToModel' );
    use_ok( 'Genome::Model::Command::Build::Assembly::AssignReadSetToModel::454' );
    use_ok( 'Genome::Model::Command::Build::Assembly::FilterReadSet' );
    use_ok( 'Genome::Model::Command::Build::Assembly::FilterReadSet::Seqclean' );
    use_ok( 'Genome::Model::Command::Build::Assembly::TrimReadSet' );
    use_ok( 'Genome::Model::Command::Build::Assembly::TrimReadSet::Sfffile' );
    use_ok( 'Genome::Model::Command::Build::Assembly::AddReadSetToProject' );
    use_ok( 'Genome::Model::Command::Build::Assembly::AddReadSetToProject::Newbler' );
    use_ok( 'Genome::Model::Command::Build::Assembly::Assemble' );
    use_ok( 'Genome::Model::Command::Build::Assembly::Assemble::Newbler' );
};

my %pp_0_params = (
		   name => 'test_assembly_processing_profile_1',
		   assembler_name => 'newbler',
		   assembler_params => '-a 0',
		   read_filter_name => 'seqclean',
		   read_trimmer_name => 'sfffile',
		   sequencing_platform => '454',
		   );

my $pp = Genome::ProcessingProfile::Assembly->create(%pp_0_params);
ok(!$pp, "correctly failed to make a processing profile with no assembler version specified");

my %pp_1_params = (
		   name => 'test_assembly_processing_profile_1',
		   assembler_name => 'newbler',
		   assembler_params => '-a 0',
		   assembler_version => '2.0.00.17',
		   read_filter_name => 'seqclean',
		   read_trimmer_name => 'sfffile',
		   sequencing_platform => '454',
		   );

my %pp_2_params = (
		   name => 'test_assembly_processing_profile_2',
		   assembler_name => 'newbler',
		   assembler_version => '2.0.00.17',
		   assembler_params => '-a 0',
		   sequencing_platform => '454',
		   );

my @pp_params = (\%pp_1_params,\%pp_2_params);

my $skip_assemble = 1;

my $model_base_name = 'test_assembly_model';
my $subject_name = 'H_FY-454_96normal_tspset3_indel';
my $subject_type = 'sample_name';

for (my $i=0; $i < scalar(@pp_params); $i++) {
    my $pp_params = $pp_params[$i];
    my $model_name = $model_base_name .'_'. $i;
    my %pp_params = %{$pp_params};
    my $pp = Genome::ProcessingProfile::Assembly->create(%pp_params);

    ok($pp, 'creation worked assembly processing profile');
    isa_ok($pp ,'Genome::ProcessingProfile::Assembly');

    for my $key (keys %pp_params) {
        is($pp->$key,$pp_params{$key},"$key accessor");
    }
    my $data_directory = File::Temp::tempdir(CLEANUP => 1);
    my $model_define = Genome::Model::Command::Define::Assembly->create(
                                                                        processing_profile_name => $pp->name,
                                                                        model_name => $model_name,
                                                                        subject_name => $subject_name,
                                                                        subject_type => $subject_type,
                                                                        data_directory => $data_directory,
                                                                    );
    isa_ok($model_define,'Genome::Model::Command::Define::Assembly');
    &_trap_messages($model_define);
    ok($model_define->execute,'execute '. $model_define->command_name);

    my @model_status_messages = $model_define->status_messages();
    my @model_warning_messages = $model_define->warning_messages();
    my @model_error_messages = $model_define->error_messages();

    ok(scalar(@model_status_messages), $model_define->command_name .' generated status messages');
    ok(scalar(@model_warning_messages), $model_define->command_name .' generated warning messages');
    like($model_warning_messages[0],qr(model symlink .* already exists),'warning model symlink already exists');
    ok(!scalar(@model_error_messages),$model_define->command_name .' generated no error messages');

    my $model = Genome::Model->get(name => $model_name);

    isa_ok($model,'Genome::Model::Assembly');
    is($model->subject_name,$subject_name,'subject_name accessor');
    is($model->subject_type,$subject_type,'subject_type accessor');
    is($model->name,$model_name,'name accessor');
    my $add_reads_command = Genome::Model::Command::AddReads->create(
                                                                     model_id => $model->id,
                                                                     all => 1,
								     );
    isa_ok($add_reads_command,'Genome::Model::Command::AddReads');
    &_trap_messages($add_reads_command);
    ok($add_reads_command->execute(),'execute genome-model add-reads');
    my @status_messages = $add_reads_command->status_messages();
    ok(scalar(@status_messages), 'add-reads execute printed some status messages');
    ok(scalar(grep { $_ eq 'Adding all available reads to the model...!'} @status_messages), 'execute mentioned it was adding all reads');
    ok(scalar(grep { $_ eq 'Found 4 compatible read sets.' } @status_messages), 'execute mentioned it found 4 read sets');
    my @warning_messages = $add_reads_command->warning_messages();
    is(scalar(@warning_messages), 0, 'execute generated no warning messages');
    my @error_messages = $add_reads_command->error_messages();
    is(scalar(@error_messages), 0, 'execute generated no error messages');

    my $assembly_builder = Genome::Model::Command::Build::Assembly->create(
                                                                           model_id => $model->id,
                                                                           auto_execute => 0,
									   );

    isa_ok($assembly_builder,'Genome::Model::Command::Build::Assembly');
    &_trap_messages($assembly_builder);

    ok($assembly_builder->execute,'execute assembly builder');
    @status_messages = $assembly_builder->status_messages();

    # Each execute generates a message per ReadSet, plus 4 more for the build's 4 sub-steps (5 total)
    # so for 8 ReadSets = 8 * 5 = 40
    # plus 2 more for scheduling reference sequence / Build::Assembly::Assemble
    #is(scalar(@status_messages), 42, 'executing builder generated 42 messages');
    for(my $i = 0; $i < 4; $i++) {
	my $index = 0;
        like($status_messages[$index++], qr(^Scheduling for Genome::InstrumentData::454 with id .*), 'Found scheduling InstrumentData messages');
        like($status_messages[$index++], qr(^Scheduled Genome::Model::Command::Build::Assembly::AssignReadSetToModel),
             'Found Scheduled...AssignReadSetToModel message');
        if ($pp_params->{'read_filter_name'}) {
            like($status_messages[$index++], qr(^Scheduled Genome::Model::Command::Build::Assembly::FilterReadSet),
                 'Found Scheduled...FilterReadSet messages');
        }

        if ($pp_params->{'read_trimmer_name'}) {
            like($status_messages[$index++], qr(^Scheduled Genome::Model::Command::Build::Assembly::TrimReadSet),
                 'Found Scheduled...TrimReadSet messages');
        }

        like($status_messages[$index++], qr(^Scheduled Genome::Model::Command::Build::Assembly::AddReadSetToProject),
             'Found Scheduled...AddReadSetToProject messages');
        splice(@status_messages, 0, $index);
    }
    is($status_messages[0],'Scheduling single_instance for stage assemble', 'Found single_instance message');
    like($status_messages[1], qr(^Scheduled Genome::Model::Command::Build::Assembly::Assemble),
	 'Found Build Assembly message');

    @warning_messages = $assembly_builder->warning_messages;
    is(scalar(@warning_messages), 0, 'executing builder generated no warning messages');
    @error_messages = $assembly_builder->error_messages;
    is(scalar(@error_messages), 0, 'executing builder generated no error messages');

    for my $class ($assembly_builder->setup_project_job_classes) {
        my @events = $class->get(model_id => $model->id);

        for my $event (@events) {
            &_trap_messages($event);
            # Executing AddReadSetToProject events runs an external program that can
            # print to stdout.  It's failure is properly caught by the caller, so we're
            # not bothering to make sure the message is correct

            my $foo;
            unless ($turn_on_messages) {
                $foo = &_disable_std_out_err();
            }
            my $rv = $event->execute();

            unless ($turn_on_messages) {
                &_enable_std_out_err($foo);
            }

            ok($rv,"execute $class event");
            @warning_messages = $assembly_builder->warning_messages;
            is(scalar(@warning_messages), 0, 'event execution produced no warning messages');
            @error_messages = $assembly_builder->error_messages;
            is(scalar(@error_messages), 0, 'event execution produced no error messages');
        }
    }
    is($model->assembly_project_xml_file,
       $model->data_directory .'/assembly/454AssemblyProject.xml',
       'expected path to assembly project xml file');
    ok(-s $model->assembly_project_xml_file, '454AssemblyProject.xml file exists with size');

    my $xml_asm_version = Genome::Model::Tools::454::Newbler->get_newbler_version_from_xml_file($model->assembly_project_xml_file);
    is($xml_asm_version, $pp_params->{assembler_version}, 'verified correct assembler version');

    my @assemble_events = Genome::Model::Command::Build::Assembly::Assemble->get(model_id => $model->id);
    is(scalar(@assemble_events),1,'one assemble event for project');

    my $assemble = $assemble_events[0];

    isa_ok($assemble,'Genome::Model::Command::Build::Assembly::Assemble');
  SKIP: {
      skip "assemble takes a long time", $skip_assemble;
      ok($assemble->execute,'execute assemble project');
  }
    my @verify_events = Genome::Model::Command::Build::VerifySuccessfulCompletion->get(model_id => $model->id);

    is(scalar(@verify_events),1,'one verify event for project');
    my $verify = $verify_events[0];
    isa_ok($verify,'Genome::Model::Command::Build::VerifySuccessfulCompletion');
  SKIP: {
      skip 'no reason to verify if we skipped assemble', $skip_assemble;
      ok($verify->execute,'execute verify_succesful_completion on build');
  }
    rmtree($model->data_directory);
}
exit;

sub _trap_messages {
    my $obj = shift;

    $obj->dump_error_messages($turn_on_messages);
    $obj->dump_warning_messages($turn_on_messages);
    $obj->dump_status_messages($turn_on_messages);
    $obj->queue_error_messages(1);
    $obj->queue_warning_messages(1);
    $obj->queue_status_messages(1);
}


# Returns a "token" that can be used later to re-enable them
sub _disable_std_out_err {
    open my $oldout, ">&STDOUT"     or die "Can't dup STDOUT: $!";
    open my $olderr, ">&", \*STDERR or die "Can't dup STDERR: $!";

    open(STDOUT,'>/dev/null');
    open(STDERR,'>/dev/null');

    return { oldout => $oldout, olderr => $olderr };
}

sub _enable_std_out_err {
    my $oldout = $_[0]->{'oldout'};
    my $olderr = $_[0]->{'olderr'};

    open STDOUT, ">&", $oldout or die "Can't dup \$oldout: $!";
    open STDERR, ">&", $olderr or die "Can't dup \$olderr: $!";
}
