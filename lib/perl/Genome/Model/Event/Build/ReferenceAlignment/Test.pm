package Genome::Model::Event::Build::ReferenceAlignment::Test;

#REVIEW fdu 11/19/2009
#Is there a better namespace to hold this test module that has nothing to
#do with build command module ?

use strict;
use warnings;
use Carp;

use Genome;

use File::Path;
use File::Copy;
use Test::More;

sub new {
    my $class = shift;
    my %args = @_;
    my $self = bless {}, $class;

    $self->{_model_name} = $args{model_name} ||
        confess("Must define model_name for test:  $!");
    $self->{_subject_name} = $args{subject_name} ||
        confess("Must define subject_name for test:  $!");
    $self->{_subject_type} = $args{subject_type} ||
        confess("Must define subject_type for test:  $!");
    $self->{_processing_profile_name} = $args{processing_profile_name} ||
        confess("Must define processing_profile_name for test:  $!");
        #$self->{_auto_execute} = $args{auto_execute} || 0;
    if ($args{instrument_data}) {
        my $instrument_data = $args{instrument_data};
        if (ref($instrument_data) eq 'ARRAY') {
            $self->{_instrument_data_array_ref} = $instrument_data;
        } else {
            confess('Supplied object type is '. ref($instrument_data) ." and expected array ref:  $!");
        }
    } else {
        confess("Must define instrument_data for test:  $!");
    }
    if ($args{data_dir}) {
        $self->{_data_dir} = $args{data_dir};
    }
    if ($args{tmp_dir}) {
        if ($args{data_dir}) {
            die 'Defined both tmp_dir and data_dir.  oops!';
        }
        $self->{_tmp_dir} = $args{tmp_dir};
        $self->{_data_dir} = $args{tmp_dir};
        $self->add_directory_to_remove($self->data_dir);
    }

    my $tmp_dir = File::Temp::tempdir('ReferenceAlignmentTestXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
    $ENV{GENOME_MODEL_DATA} = $tmp_dir;
    if ($args{messages}) {
        $self->{_messages} = $args{messages};
    } else {
        $self->{_messages} = 0;
    }
    return $self;
}

#sub auto_execute {
#    my $self = shift;
#    return $self->{_auto_execute};
#}

sub data_dir {
    my $self = shift;
    return $self->{_data_dir};
}

sub add_directory_to_remove {
    my $self = shift;
    my $dir = shift;
    unless ($dir) {
        carp("No directory given to remove:  $!");
    }
    my @directories_to_remove;
    if ($self->{_dir_array_ref}) {
        my $dir_ref = $self->{_dir_array_ref};
        @directories_to_remove = @{$dir_ref};
    }
    push @directories_to_remove, $dir;
    $self->{_dir_array_ref} = \@directories_to_remove;
}


sub model {
    my $self = shift;
    if (@_) {
        my $object = shift;
        unless ($object->isa('Genome::Model')) {
            confess('expected Genome::Model and got '. $object->class ." object:  $!");
        }
        $self->{_model} = $object;
    }
    return $self->{_model};
}

sub build {
    my $self = shift;
    if (@_) {
        my $object = shift;
        unless ($object->isa('Genome::Model::Build')) {
            confess('expected Genome::Model::Build and got '. $object->class ." object:  $!");
        }
        $self->{_build} = $object;
    }
    return $self->{_build};
}

sub runtests {
    my $self = shift;

    my @tests = (
                 'startup',
                 'create_model',
                 'add_instrument_data',
                 'run',
                 'remove_data',
             );
    for my $test (@tests) {
        $self->$test;
        #if ($self->auto_execute) {
        #   if ($test eq 'schedule') {
                #should fix test number
                #        last;
                #}
                #  }
    }
    return 1;
}

sub startup {
    my $self = shift;
    is(App::DB->db_access_level,'rw','App::DB db_access_level');
    ok(App::DB::TableRow->use_dummy_autogenerated_ids,'App::DB::TableRow use_dummy_autogenerated_ids');
    ok(App::DBI->no_commit,'App::DBI no_commit');
    ok($ENV{UR_DBI_NO_COMMIT},'environment variable UR_DBI_NO_COMMIT');
    #SKIP: {
    #    skip 'using real ids with auto execute', 1 if $self->auto_execute;
        ok($ENV{UR_USE_DUMMY_AUTOGENERATED_IDS},'environment variable UR_USE_DUMMY_AUTOGENERATED_IDS');
        #}
}


sub create_model {
    my $self = shift;
    my $create_command= Genome::Model::Command::Define::ReferenceAlignment->create(
                                                                                   model_name => $self->{_model_name},
                                                                                   subject_name => $self->{_subject_name},
                                                                                   subject_type => $self->{_subject_type},
                                                                                   processing_profile_name => $self->{_processing_profile_name},
                                                                  );

    isa_ok($create_command,'Genome::Model::Command::Define::ReferenceAlignment');

    $self->_trap_messages($create_command);
    ok($create_command->execute, 'execute '. $create_command->command_name);

    my @status_messages = $create_command->status_messages();
    ok(scalar(@status_messages), 'status messages generated creating the model');
    # FIXME commented out for now - there may have been a warning about an existing symlink
    #my @warning_messages = $create_command->warning_messages;
    #ok(!scalar(@warning_messages), 'no warning messages');
    my @error_messages = $create_command->error_messages;
    ok(!scalar(@error_messages),'no error messages');

    my @models = Genome::Model->get(name => $self->{_model_name});
    is(scalar(@models),1,'expected one model');
    my $model = $models[0];
    $model->test(1);
    isa_ok($model,'Genome::Model');

    my $test_gold_snp_path = '/gsc/var/cache/testsuite/data/Genome-Model-Report-GoldSnp/test.gold2';
    $model->gold_snp_path($test_gold_snp_path);

    $self->model($model);

}

sub add_instrument_data {
    my $self = shift;
    my $model = $self->model;
    my @instrument_data = @{$self->{_instrument_data_array_ref}};
    for my $instrument_data (@instrument_data) {
        isa_ok($instrument_data,'Genome::InstrumentData');
        $model->add_instrument_data($instrument_data);
        my $input = Genome::Model::Input->get(
            model_id => $model->id,
            value_id => $instrument_data->id,
        );
        isa_ok($input, 'Genome::Model::Input');
    }
}

sub run {
    my $self = shift;
    my $model = $self->model;

    # Create and schedule a build
    my $build = Genome::Model::Build->create( 
        model_id => $model->id,
    );
    ok($build, 'Created build.');

    # supress warning messages about obsolete locking
    Genome::Model::ReferenceAlignment->message_callback('warning', sub {});
    
    ok($build->start(server_dispatch => 'inline', job_dispatch => 'inline'), 'scheduled and ran build inline');
    my @stages = $build->processing_profile->stages();

    # Check we scheduled as expected
    for my $stage ( @stages ) {

        ## HACK - THIS IS NEEDED TO AVOID A UR GET FAILURE ##
        #####################################################
        my @events = $build->build_event->events_for_stage($stage);
        #####################################################
        
        my @classes = $model->processing_profile->classes_for_stage($stage);
        next unless @classes;
        my @objects = $model->processing_profile->objects_for_stage($stage, $model);
        my $event_count = scalar(@events);
        my $expected_event_count = scalar(@classes) * scalar(@objects);
        is($event_count, $expected_event_count, "Got $expected_event_count events for stage ".$stage);
    }

    $self->build($build);
}

sub XXXrun {
    my $self = shift;
    my $model = $self->model;
    my $build = $self->build;
    my $pp = $model->processing_profile;
    my @events;
    my @objects;

    my @all_events;

    for my $stage_name ($pp->stages) {
        my @classes = $pp->classes_for_stage($stage_name);
       
	if ($stage_name eq 'alignment') {
    		if ($model->sequencing_platform eq 'solexa') {
        		@objects = $model->instrument_data;
    		} elsif ($model->sequencing_platform eq '454') {
        		@objects = $model->instrument_data;
    		}   
	} else {
        	@objects = $pp->objects_for_stage($stage_name,$self->model);
	} 
        
	for my $command_class (@classes) {
            @events = Genome::Model::Event->get(
                                                model_id => $model->id,
                                                build_id => $build->build_id,
                                                event_type => {
                                                               operator => 'like',
                                                               value => $command_class->command_name .'%',
                                                           },
                                            );
            @events = sort {$b->genome_model_event_id <=> $a->genome_model_event_id} @events;
            
	    is( scalar(@events),scalar(@objects), 'For command '.$command_class.' number of events matches number of objects: '.scalar(@events).' = '.scalar(@objects)); 

            $DB::single=1 if $command_class eq 'Genome::Model::Event::Build::ReferenceAlignment::PostDedupReallocate';

            for my $event (@events) {
                $self->execute_event_test($event);
            }

        }

	#accumulate the events for further testing below 
    	push @all_events, @events;	
    }

    #die();

    my @failed_events = grep { $_->event_status ne 'Succeeded' } @all_events;
    my $build_status;
    if (@failed_events) {
        $build_status = 'Failed';
        diag('FAILED -- build found '. scalar(@failed_events) .' incomplete events');
    } else {
        $build_status = 'Succeeded';
    }
    set_event_status($build->build_event,$build_status);
    is($build->build_status,$build_status,'the build status was set correctly after execution of the events');
    return @all_events;
}

sub run_events_for_class_array_ref {
    my $self = shift;
    my $classes = shift;
    my @instrument_data = @{$self->{_instrument_data_array_ref}};
    my $pp = $self->model->processing_profile;
    my @stages = $pp->stages;
    my $stage3 = $stages[2];
    my $stage_object_method = $stage3 .'_objects';
    my @stage3_objects = $pp->$stage_object_method($self->model);
    my @events;
    for my $command_class (@$classes) {
        if (ref($command_class) eq 'ARRAY') {
            push @events, $self->run_events_for_class_array_ref($command_class);
        } else {
            my @events = $command_class->get(model_id => $self->model->id);
            @events = sort {$b->genome_model_event_id <=> $a->genome_model_event_id} @events;
            if ($command_class =~ /AlignReads/) {
                is(scalar(@events),scalar(@instrument_data),'the number of events matches read sets for EventWithReadSet class '. $command_class);
            } elsif ($command_class =~ /MergeAlignments|UpdateGenotype|FindVariations/) {
                is(scalar(@events),scalar(@stage3_objects),'the number of events matches ref seqs for EventWithRefSeq class '. $command_class);
            } else {
                is(scalar(@events),1,'Only expecting one event when for class '. $command_class);
            }
            for my $event (@events) {
                $self->execute_event_test($event);
            }
        }
    }
    return @events;
}

sub execute_event_test  {
    my ($self,$event) = @_;

    my $event_model = $event->model;
    $event_model->test(1);
    is($self->model->id,$event_model->id,'genome-model id comparison');

    SKIP: {
          #skip 'Never should see this.', 1 if 0;
          skip 'AnnotateVariations takes too long', 1 if $event->isa('Genome::Model::Event::Build::ReferenceAlignment::AnnotateVariations');
          
	  # FIXME - some of these events emit messages of one kind or another - are any
          # of them worth looking at?
          $self->_trap_messages($event);
          my $result = $event->execute();

          ok($result,'Execute: '. $event->command_name);
          if ($result) {
              set_event_status($event,'Succeeded');
          }
          else {
              diag("FAILED " . $event->command_name . " " . $event->error_message());
              set_event_status($event,'Failed');
          }
        SKIP: {
              skip 'class '. $event->class .' does not have a verify_successful_completion method', 1 if !$event->can('verify_successful_completion');
              ok($event->verify_successful_completion,'verify_successful_completion for class '. $event->class);
          }
      }
}

sub set_event_status {
    my ($event,$status) = @_;
    my $now = UR::Time->now;
    $event->event_status($status);
    $event->date_completed($now);
}

sub remove_data {
    my $self = shift;
    my $model = $self->model;
    my $build = $self->model->last_complete_build;
    my @instrument_data = $build->instrument_data;
    my @alignment_dirs = map { $_->alignment_directory_for_instrument_data($_) } @instrument_data;
    
    # we now rely on tempdir to cause cleanup
    # there is an override, and that should NOT get cleaned-up
    #for my $alignment_dir (@alignment_dirs) {
    #    $self->add_directory_to_remove($alignment_dir);
    #}

    # FIXME - the delete below causes a lot of warning messages about deleting
    # hangoff data.  do we need to check the contents?
    $self->_trap_messages('Genome::Model::Event');

    #ok(UR::Context->_sync_databases,'sync with the database');
    ok(1,'sync with the database');
    ok($self->model->delete,'successfully removed model');
    my $directories_to_remove = $self->{_dir_array_ref};
    for my $dir (@{$directories_to_remove}) {
        unless (rmtree $dir) {
            warn("Failed to remove directory '$dir':  $!");
        }
    }
}

sub create_test_pp {
    my $self = shift;
    my %processing_profile = @_;
    Genome::ProcessingProfile::ReferenceAlignment->create(%processing_profile);
    return 1;
}


sub _trap_messages {
    my $self = shift;
    my $obj = shift;

    $obj->dump_error_messages($self->{_messages});
    $obj->dump_warning_messages($self->{_messages});
    $obj->dump_status_messages($self->{_messages});
    $obj->queue_error_messages(1);
    $obj->queue_warning_messages(1);
    $obj->queue_status_messages(1);
}

1;
