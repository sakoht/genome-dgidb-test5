package Genome::Model::Command::Build::ReferenceAlignment::Test;

use strict;
use warnings;
use Carp;

use Genome;
use Genome::Model::Tools::Maq::CLinkage0_6_5;
use Genome::Model::Tools::Maq::MapSplit;

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
    $self->{_auto_execute} = $args{auto_execute} || 0;
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

    my $tmp_dir = File::Temp::tempdir('ReferenceAlignmentTestXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 0);
    $ENV{GENOME_MODEL_ROOT} = $tmp_dir;
    $ENV{GENOME_MODEL_DATA} = $tmp_dir;
    Genome::Utility::FileSystem->create_directory(
                                                  Genome::Config->model_links_directory
                                              );
    if ($args{messages}) {
        $self->{_messages} = $args{messages};
    } else {
        $self->{_messages} = 0;
    }
    return $self;
}

sub auto_execute {
    my $self = shift;
    return $self->{_auto_execute};
}

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
        unless ($object->isa('Genome::Model::Command::Build::ReferenceAlignment')) {
            confess('expected Genome::Model::Command::Build::ReferenceAlignment and got '. $object->class ." object:  $!");
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
                 'schedule',
                 'run',
                 'remove_data',
             );
    for my $test (@tests) {
        $self->$test;
        if ($self->auto_execute) {
            if ($test eq 'schedule') {
                #should fix test number
                last;
            }
        }
    }
    return 1;
}

sub startup {
    my $self = shift;
    is(App::DB->db_access_level,'rw','App::DB db_access_level');
    ok(App::DB::TableRow->use_dummy_autogenerated_ids,'App::DB::TableRow use_dummy_autogenerated_ids');
    ok(App::DBI->no_commit,'App::DBI no_commit');
    ok($ENV{UR_DBI_NO_COMMIT},'environment variable UR_DBI_NO_COMMIT');
    SKIP: {
        skip 'using real ids with auto execute', 1 if $self->auto_execute;
        ok($ENV{UR_USE_DUMMY_AUTOGENERATED_IDS},'environment variable UR_USE_DUMMY_AUTOGENERATED_IDS');
    }
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

    my $base_alignment_directory = Genome::Config->alignment_links_directory .'/'.
        $model->read_aligner_name .'/'. $model->reference_sequence_name;
    Genome::Utility::FileSystem->create_directory($base_alignment_directory);
}

sub add_instrument_data {
    my $self = shift;
    my $model = $self->model;
    my @instrument_data = @{$self->{_instrument_data_array_ref}};
    for my $instrument_data (@instrument_data) {
        isa_ok($instrument_data,'Genome::InstrumentData');
        my $assign_command = Genome::Model::Command::InstrumentData::Assign->create(
                                                                         model_id => $model->id,
                                                                         instrument_data_id => $instrument_data->id,
                                                                     );
        isa_ok($assign_command,'Genome::Model::Command::InstrumentData::Assign');
        ok($assign_command->execute(),'execute '. $assign_command->command_name);

        my $ida = Genome::Model::InstrumentDataAssignment->get(
                                                               model_id => $model->id,
                                                               instrument_data_id => $instrument_data->id,
                                                           );
        isa_ok($ida,'Genome::Model::InstrumentDataAssignment');
        ok(!$ida->first_build_id,'undef first_build_id for InstrumentDataAssignment');
    }
}

sub schedule {
    my $self = shift;
    my $model = $self->model;

    my $build = Genome::Model::Command::Build::ReferenceAlignment->create(
                                                                          model_id => $model->id,
                                                                          auto_execute => $self->auto_execute,
                                                                      );
    isa_ok($build,'Genome::Model::Command::Build::ReferenceAlignment');

    # supress warning messages about obsolete locking
    Genome::Model::ReferenceAlignment->message_callback('warning', sub {});
    $self->_trap_messages($build);
    ok($build->execute(), 'execute genome-model build reference-alignment');

    my @status_messages = $build->status_messages();
    my @warning_messages = $build->warning_messages();
    my @error_messages = $build->error_messages();

    # FIXME This code is used in several different tests, each of which generate different numbers
    # of messages about scheduling...  Is there some other method of making sure the right
    # number of downstream events were scheduled?
    #if ($model->sequencing_platform eq '454') {
        ok(scalar(grep { m/^Scheduling for Test::MockObject with id .*/} @status_messages),
           'Saw a message about Test::MockObject');
    #} else {
    #    ok(scalar(grep { m/^Scheduling jobs for .* read set/} @status_messages),
    #       'Saw a message about ReadSet');
    #}
    SKIP : {
        skip 'No AssignRun step for Solexa', 1 if $model->sequencing_platform eq 'solexa' || $model->sequencing_platform eq '454';
        ok(scalar(grep { m/^Scheduled Genome::Model::Command::Build::ReferenceAlignment::AssignRun/} @status_messages),
           'Saw a message about AssignRun');
    }
    ok(scalar(grep { m/^Scheduled Genome::Model::Command::Build::ReferenceAlignment::AlignReads/} @status_messages),
       'Saw a messages about  AlignReads');
    my $variation_granularity;
    if ($model->sequencing_platform eq '454') {
        $variation_granularity = 1;
    } elsif ($model->sequencing_platform eq 'solexa') {
        $variation_granularity = 1; #was 3 
    } else {
        die ('Unrecognized sequencing platform in ReferenceAlignment test: '. $model->sequencing_platform);
    }
    SKIP : {
        skip 'No reference sequence messages for 454', 1 if $model->sequencing_platform eq '454';
        is(scalar(grep { m/^Scheduling jobs for reference sequence .*/} @status_messages),
           4, "Got 4 reference_sequence messages");
    }
    SKIP : {
        skip 'No merge alignments for Solexa', 1 if $model->sequencing_platform eq 'solexa';
    is(scalar(grep { m/^Scheduled Genome::Model::Command::Build::ReferenceAlignment::MergeAlignments/} @status_messages),
       $variation_granularity, "Got $variation_granularity MergeAlignments messages");
    } 
    SKIP : {
        skip 'No UpdateGenotype step for 454', 1 if $model->sequencing_platform eq '454'; 
    is(scalar(grep { m/^Scheduled Genome::Model::Command::Build::ReferenceAlignment::UpdateGenotype/} @status_messages),
           $variation_granularity, "Got $variation_granularity UpdateGenotype messages");
    }
   is(scalar(grep { m/^Scheduled Genome::Model::Command::Build::ReferenceAlignment::FindVariations/} @status_messages),
       $variation_granularity, "Got $variation_granularity FindVariations messages");
    SKIP : {
        skip 'No PostprocessVariations step for 454 or solexa', 1 if $model->sequencing_platform eq '454' || $model->sequencing_platform eq 'solexa';
    is(scalar(grep { m/^Scheduled Genome::Model::Command::Build::ReferenceAlignment::PostprocessVariations/} @status_messages),
       $variation_granularity, "Got $variation_granularity PostprocessVariations messages");
    }
    SKIP : {
        skip 'No AnnotateVariations step for 454 or solexa', 1 if $model->sequencing_platform eq '454' || $model->sequencing_platform eq 'solexa';
        is(scalar(grep { m/^Scheduled Genome::Model::Command::Build::ReferenceAlignment::AnnotateVariations/} @status_messages),
           $variation_granularity, "Got $variation_granularity AnnotateVariations messages");
    }
   # Not checking warning messages - for now, there are some relating to obsolete locking
    my $expected_errors = $model->sequencing_platform eq 'solexa' && $model->dna_type eq 'genomic dna' ? 1 : 0;
    is(scalar(@error_messages), $expected_errors, "found $expected_errors errors");

    $self->build($build);
}

sub run {
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
        diag("FAILED " . $build->command_name .' found '. scalar(@failed_events) .' incomplete events');
    } else {
        $build_status = 'Succeeded';
    }
    set_event_status($build,$build_status);
    is($build->event_status,$build_status,'the build status was set correctly after execution of the events');
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
          skip 'AnnotateVariations takes too long', 1 if $event->isa('Genome::Model::Command::Build::ReferenceAlignment::AnnotateVariations');
          
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
    my @idas = $model->instrument_data_assignments;
    my @alignment_dirs = map { $_->alignment_directory } @idas;
    
    # we now rely on tempdir to cause cleanup
    # there is an override, and that should NOT get cleaned-up
    #for my $alignment_dir (@alignment_dirs) {
    #    $self->add_directory_to_remove($alignment_dir);
    #}

    # FIXME - the delete below causes a lot of warning messages about deleting
    # hangoff data.  do we need to check the contents?
    $self->_trap_messages('Genome::Model::Event');

    ok(UR::Context->_sync_databases,'sync with the database');
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
    $processing_profile{bare_args} = [];
    my $create_pp_command = Genome::ProcessingProfile::Command::Create::ReferenceAlignment->create(%processing_profile);
    unless($create_pp_command->execute()) {
        confess("Failed to create processing_profile for test:  $!");
    }
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
