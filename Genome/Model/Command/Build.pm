package Genome::Model::Command::Build;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Build {
    is => [ 'Genome::Model::Event' ],
    has => [
        data_directory => { via => 'build' },
        auto_execute   => {
                           is => 'Boolean',
                           default_value => 1,
                           is_transient => 1,
                           is_optional => 1,
                           doc => 'The build will execute genome model build run-jobs(default_value=1)',
                       },
    ],
    doc => "build the model with currently assigned instrument data according to the processing profile",
};

sub sub_command_sort_position { 3 }

sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    unless ($self) {
        $class->error_message("Failed to create build command: " . $class->error_message());
        return;
    }
    unless (defined $self->auto_execute) {
        $self->auto_execute(1);
    }
    my $model = $self->model;
    unless ($self->build_id) {
        my $current_running_build = $model->current_running_build;
        if ($current_running_build) {
            $self->build_id($current_running_build->build_id);
        } else {
            my $build = Genome::Model::Build->create(
                                                     model_id => $model->id,
                                                   );
            unless ($build) {
                $self->error_message('Failed to create new build for model '. $model->id);
                $self->delete;
                return;
            }
            $self->build_id($build->build_id);
        }
    }
    my @build_events = Genome::Model::Command::Build->get(
                                                          model_id => $model->id,
                                                          build_id => $self->build_id,
                                                          genome_model_event_id => { operator => 'ne', value => $self->id},
                                                      );
    if (scalar(@build_events)) {
        my $error_message = 'Found '. scalar(@build_events) .' build event(s) that already exist for build id '.
            $self->build_id;
        for (@build_events) {
            $error_message .= "\n". $_->desc ."\t". $_->event_status ."\n";
        }
        $self->error_message($error_message);
        $self->delete;
        return;
    }
    $self->date_scheduled(UR::Time->now());
    $self->date_completed(undef);
    $self->event_status('Running');
    $self->user_name($ENV{'USER'});

    my $build = $self->build;
    unless ($build) {
        $self->error_message('No build found for build id '. $self->build_id);
        $self->delete;
        return;
    }

    return $self;
}

sub clean {
    my $self=shift;
    my @events = Genome::Model::Event->get(parent_event_id=>$self->id);
    for my $event (@events) {
        $event->delete;
    }
    if ($self->model->current_running_build_id == $self->id) {
        $self->model->current_running_build_id(undef);
    }
    if ($self->model->last_complete_build_id == $self->id) {
        $self->model->last_complete_build_id(undef);
    }
    $self->delete;
    return;
}




sub Xresolve_data_directory {
    my $self = shift;
    my $model = $self->model;
    return $model->data_directory . '/build' . $self->id;
}

sub execute {
    my $self = shift; 
    my $build = $self->build;
    unless ($build) {
        $self->error_message('No build found for build id '. $self->build_id);
        return;
    }
    my @events = grep { $_->id != $self->id } $build->events;
    if (scalar(@events)) {
        my $error_message = 'Build '. $build->build_id .' already has events.' ."\n";
        for (@events) {
            $error_message .= "\t". $_->desc .' '. $_->event_status ."\n";
        }
        $error_message .= 'For build event: '. $self->desc .' '. $self->event_status;
        return;
    }

    $self->create_directory($self->data_directory);
    my $run_jobs_script = $self->data_directory .'/run_jobs_'. $build->build_id .'.pl';
    open(FILE,'>'.$run_jobs_script) || die ('Failed to open run jobs script: '. $run_jobs_script .":  $!");

    print FILE "#!/gsc/bin/perl\n
                use strict;\n
                use warnings;\n
                use Genome;\n";
    print FILE 'my $rv;'. "\n";

    my $pp = $self->model->processing_profile;
    for my $stage_name ($pp->stages) {
        my @scheduled_objects = $self->_schedule_stage($stage_name);
        unless (@scheduled_objects) {
            $self->error_message('Problem with build('. $self->build_id .") objects not scheduled for classes:\n".
                                 join("\n",$pp->classes_for_stage($stage_name)));
            $self->event_status('Running');
            #    die;
        }
        if (!defined $self->auto_execute) {
            # transent properties with default_values are not re-initialized when loading object from data source
            $self->auto_execute(1);
        }
        my $command = 'genome model build run-jobs --model-id='. $build->model_id .' --build-id='. $build->build_id .' --stage-name='. $stage_name;
        print FILE '$rv' . " = system('$command');\n";
        print FILE 'unless ($rv == 0) { die $!; }'. "\n";
    }
    close(FILE);
    # this is really more of a 'testing' flag and may be more appropriate named such
    if ($self->auto_execute) {
        my $cmdline = 'bsub -H -q long -u '. $ENV{USER} .'@genome.wustl.edu perl '. $run_jobs_script;
        my $bsub_output = `$cmdline`;
        my $retval = $? >> 8;

        if ($retval) {
            $self->error_message("bsub returned a non-zero exit code ($retval), bailing out");
            return;
        }
        my $bsub_job_id;
        if ($bsub_output =~ m/Job <(\d+)>/) {
            $bsub_job_id = $1;
        } else {
            $self->error_message('Unable to parse bsub output, bailing out');
            $self->error_message("The output was: $bsub_output");
            return;
        }
        $self->lsf_job_id($bsub_job_id);
        $self->mail_summary;
        my $resume = sub { `bresume $bsub_job_id`};
        UR::Context->create_subscription(method => 'commit', callback => $resume);
    }
    return 1;
}

sub resolve_stage_name_for_class {
    my $self = shift;
    my $class = shift;
    my $pp = $self->model->processing_profile;
    for my $stage_name ($pp->stages) {
        my $found_class = grep { $class =~ /^$_/ } $pp->classes_for_stage($stage_name);
        if ($found_class) {
            return $stage_name;
        }
    }
    my $error_message = "No class found for '$class' in build ". $self->class ." stages:\n";
    for my $stage_name ($pp->stages) {
        $error_message .= $stage_name ."\n";
        for my $class ($pp->classes_for_stage($stage_name)) {
            $error_message .= "\t". $class ."\n";
        }
    }
    $self->error_message($error_message);
    return;
}

sub events_for_stage {
    my $self = shift;
    my $stage_name = shift;
    my $pp = $self->model->processing_profile;
    my @events;
    for my $class ($pp->classes_for_stage($stage_name)) {
        push @events, $self->events_for_class($class);
    }
    return @events;
}

sub events_for_class {
    my $self = shift;
    my $class = shift;

    my @class_events = $class->get(
                                   model_id => $self->model_id,
                                   build_id => $self->build_id,
                               );

    #Not sure if every class is supposed to have return of events
    #but adding the line below makes the tests pass for now
    return unless @class_events;

    my @sorted_class_events;
    if ($class_events[0]->id =~ /^-/) {
        @sorted_class_events = sort {$b->id <=> $a->id} @class_events;
    } else {
        @sorted_class_events = sort {$a->id <=> $b->id} @class_events;
    }
    return @sorted_class_events;
}

sub abandon_incomplete_events_for_stage {
    my $self = shift;
    my $stage_name = shift;
    my $force_flag = shift;

    my @stage_events = $self->events_for_stage($stage_name);
    my @incomplete_events = grep { $_->event_status !~ /Succeeded|Abandoned/ } @stage_events;
    if (@incomplete_events) {
        my $status_message = 'Found '. scalar(@incomplete_events) ." incomplete events for stage $stage_name:\n";
        for (@incomplete_events) {
            $status_message .= $_->id ."\t". $_->event_type ."\t". $_->event_status ."\n";
        }
        $self->status_message($status_message);
        unless (defined $force_flag) {
            my $response_1 = $self->_ask_user_question('Would you like to abandon the incomplete events?');
            if ($response_1 eq 'yes') {
                my $response_2 = $self->_ask_user_question('None of the data associated with these events will be included in further processing.  Are you sure?');
                if ($response_2 eq 'yes') {
                    for my $incomplete_event (@incomplete_events) {
                        unless ($incomplete_event->abandon) {
                            $self->error_message('Failed to abandon event '. $incomplete_event->id);
                            return;
                        }
                    }
                    return 1;
                }
            }
            # we have incomplete events but do not want to abandon
            return;
        } else {
            if ($force_flag == 1) {
                for my $incomplete_event (@incomplete_events) {
                    unless ($incomplete_event->abandon) {
                        $self->error_message('Failed to abandon event '. $incomplete_event->id);
                        return;
                    }
                }
                return 1;
            } elsif ($force_flag == 0) {
                return;
            } else {
                $self->error_messge('Illegal value '. $force_flag .' for abandon force flag.');
            }
        }
    }
    # we have no incomplete events for stage
    return 1;
}

sub continue_with_abandoned_events_for_stage {
    my $self = shift;
    my $stage_name = shift;
    my $force_flag = shift;
    
    my @stage_events = $self->events_for_stage($stage_name);
    my @abandoned_events = grep { $_->event_status eq 'Abandoned' } @stage_events;
    if (@abandoned_events) {
        my $status_message = 'Found '. scalar(@abandoned_events) ." abandoned events for stage $stage_name:\n";
        for (@abandoned_events) {
            $status_message .= $_->id ."\t". $_->event_type ."\t". $_->event_status ."\n";
        }
        $self->status_message($status_message);
        unless (defined($force_flag)) {
            my $response = $self->_ask_user_question('Would you like to continue with build, ignoring these abandoned events?');
            if ($response eq 'yes') {
                return 1;
            }
            return;
        } else {
            if ($force_flag == 1) {
                return 1;
            } elsif ($force_flag == 0) {
                return;
            } else {
                $self->error_messge('Illegal value '. $force_flag .' for continuing with abandoned force flag.');
            }
        }
    }
    return 1;
}

sub ignore_unverified_events_for_stage {
    my $self = shift;
    my $stage_name = shift;
    my $force_flag = shift;
    
    my @stage_events = $self->events_for_stage($stage_name);
    my @succeeded_events = grep { $_->event_status eq 'Succeeded' } @stage_events;
    my @can_not_verify_events = grep { !$_->can('verify_successful_completion') } @succeeded_events;
    if (@can_not_verify_events) {
        my $status_message = 'Found '. scalar(@can_not_verify_events) ." events that will not be verified:\n";
        for (@can_not_verify_events) {
            $status_message .= $_->id ."\t". $_->event_type ."\t". $_->event_status ."\n";
        }
        $self->status_message($status_message);
        unless (defined($force_flag)) {
            my $response = $self->_ask_user_question('Would you like to continue, ignoring unverified events?');
            if ($response eq 'yes') {
                return 1;
            }
            return;
        } else {
            if ($force_flag == 1) {
                return 1;
            } elsif ($force_flag == 0) {
                return;
            } else {
                $self->error_messge('Illegal value '. $force_flag .' for continuing with unverified events.');
            }
        }
    }
    return 1;
}

sub verify_successful_completion_for_stage {
    my $self = shift;
    my $stage_name = shift;
    my $force_flag = shift;

    my @stage_events = $self->events_for_stage($stage_name);
    my @succeeded_events = grep { $_->event_status eq 'Succeeded' } @stage_events;
    my @verifiable_events = grep { $_->can('verify_successful_completion') } @succeeded_events;
    my @unverified_events = grep { !$_->verify_successful_completion } @verifiable_events;
    if (@unverified_events) {
        my $status_message = 'Found '. scalar(@unverified_events) ." events that can not be verified successful:\n";
        for (@unverified_events) {
            $status_message .= $_->id ."\t". $_->event_type ."\t". $_->event_status ."\n";
        }
        $self->status_message($status_message);
        unless (defined($force_flag)) {
            my $response_1 = $self->_ask_user_question('Would you like to abandon events which failed to verify?');
            if ($response_1 eq 'yes') {
                my $response_2 = $self->_ask_user_question('Abandoning these events will exclued all data associated with these events from further analysis.  Are you sure?');
                if ($response_2 eq 'yes') {
                    for my $unverified_event (@unverified_events) {
                        unless ($unverified_event->abandon) {
                            $self->error_message('Failed to abandon event '. $unverified_event->id);
                            return;
                        }
                    }
                    return 1;
                }
            }
            return;
        } else {
            if ($force_flag == 1) {
                for my $unverified_event (@unverified_events) {
                    unless ($unverified_event->abandon) {
                        $self->error_message('Failed to abandon event '. $unverified_event->id);
                        return;
                    }
                }
                return 1;
            } elsif ($force_flag == 0) {
                return;
            } else {
                $self->error_messge('Illegal value '. $force_flag .' for continuing with unsuccessful events.');
            }
        }
    }
    return 1;
}

sub verify_successful_completion {
    my $self = shift;
    my $force_flag = shift;

    my $pp = $self->model->processing_profile;
    for my $stage_name ($pp->stages) {
        if ($stage_name eq 'verify_successful_completion') {
            last;
        }
        unless ($self->verify_successful_completion_for_stage($stage_name,$force_flag)) {
            $self->error_message('Failed to verify successful completion of stage '. $stage_name);
            return;
        }
    }
    return 1;
}

sub update_build_state {
    my $self = shift;
    my $force_flag = shift;
    my $pp = $self->model->processing_profile;
    for my $stage_name ($pp->stages) {
        if ($stage_name eq 'verify_successful_completion') {
            last;
        }
        unless ($self->abandon_incomplete_events_for_stage($stage_name,$force_flag)) {
            return;
        }
        unless ($self->continue_with_abandoned_events_for_stage($stage_name,$force_flag)) {
            return;
        }
        unless ($self->ignore_unverified_events_for_stage($stage_name,$force_flag)) {
            return;
        }
        unless ($self->verify_successful_completion_for_stage($stage_name,$force_flag)) {
            return;
        }
        $self->remove_dependencies_on_stage($stage_name);
        # Should we set the build as Abandoned
    }
    return 1;
}

sub remove_dependencies_on_stage {
    my $self = shift;
    my $stage_name = shift;
    my $pp = $self->model->processing_profile;

    my @stages = $pp->stages;
    my $next_stage_name;
    for (my $i = 0; $i < scalar(@stages); $i++) {
        if ($stage_name eq $stages[$i]) {
            $next_stage_name = $stages[$i+1];
            last;
        }
    }
    if ($next_stage_name) {
        my $dependency = 'done("'. $self->model_id .'_'. $self->build_id .'_'. $stage_name .'*")';
        my @classes = $pp->classes_for_stage($next_stage_name);
        $self->_remove_dependency_for_classes($dependency,\@classes);
    }
}

sub _remove_dependency_for_classes {
    my $self = shift;
    my $dependency = shift;
    my $classes = shift;
    for my $class (@$classes) {
        if (ref($class) eq 'ARRAY') {
            $self->_remove_dependencey_for_classes($dependency,$class);
        } else {
            my @events = $class->get(
                                     event_status => 'Scheduled',
                                     model_id => $self->model_id,
                                     build_id => $self->build_id,
                                     user_name => $ENV{'USER'},
                                 );
            for my $event (@events) {
                my $dependency_expression = $event->lsf_dependency_condition;
                unless ($dependency_expression) {
                    next;
                }
                my @current_dependencies = split(" && ",$dependency_expression);
                my @keep_dependencies;
                for my $current_dependency (@current_dependencies) {
                    if ($current_dependency eq $dependency) {
                        next;
                    }
                    push @keep_dependencies, $current_dependency;
                }
                my $new_expression = join(" && ",@keep_dependencies);
                if ($dependency_expression eq $new_expression) {
                    $self->error_message("Failed to modify dependency expression $dependency_expression by removing $dependency");
                    die;
                }
                $self->status_message("Changing dependency from '$dependency_expression' to '$new_expression' for event ". $event->id);
                my $lsf_job_id = $event->lsf_job_id;
                my $cmd = "bmod -w '$new_expression' $lsf_job_id";
                $self->status_message("Running:  $cmd");
                my $rv = system($cmd);
                unless ($rv == 0) {
                    $self->error_message('non-zero exit code returned from command: '. $cmd);
                    die;
                }
            }
        }
    }
}

sub _schedule_stage {
    my $self = shift;
    my $stage_name = shift;
    my $pp = $self->model->processing_profile;
    my @objects = $pp->objects_for_stage($stage_name,$self->model);
       my @scheduled_commands;
    foreach my $object (@objects) {
        my $object_class;
        my $object_id; 
        if (ref($object)) {
            $object_class = ref($object);
            $object_id = $object->id;
        } elsif ($object == 1) {
            $object_class = 'single_instance';
        } else {
            $object_class = 'reference_sequence';
            $object_id = $object;
        }
        if ($object_class->isa('Genome::InstrumentData')) {
            $self->status_message('Scheduling jobs for '
                . $object_class . ' '
                . $object->full_name
                . ' (' . $object->id . ')'
            );
        } elsif ($object_class eq 'reference_sequence') {
            $self->status_message('Scheduling jobs for reference sequence ' . $object_id);
        } elsif ($object_class eq 'single_instance') {
            $self->status_message('Scheduling '. $object_class .' for stage '. $stage_name);
        } else {
            $self->status_message('Scheduling for '. $object_class .' with id '. $object_id);
        }
        my @command_classes = $pp->classes_for_stage($stage_name);
        push @scheduled_commands, $self->_schedule_command_classes_for_object($object,\@command_classes);
    }
    return @scheduled_commands;
}

sub _schedule_command_classes_for_object {
    my $self = shift;
    my $object = shift;
    my $command_classes = shift;
    my $prior_event_id = shift;

    my @scheduled_commands;
    for my $command_class (@{$command_classes}) {
        if (ref($command_class) eq 'ARRAY') {
            push @scheduled_commands, $self->_schedule_command_classes_for_object($object,$command_class,$prior_event_id);
        } else {
            if ($command_class->can('command_subclassing_model_property')) {
                my $subclassing_model_property = $command_class->command_subclassing_model_property;
                unless ($self->model->$subclassing_model_property) {
                    # TODO: move into the creation of the processing profile
                    #$self->status_message("This processing profile doesNo value defined for $subclassing_model_property in the processing profile.  Skipping related processing...");
                    next;
                }
            }
            my $command;
            if ($command_class->isa('Genome::Model::EventWithRefSeq')) {
                if (ref($object)) {
                    unless ($object->isa('Genome::Model::RefSeq')) {
                        my $error_message = 'Expecting Genome::Model::RefSeq for EventWithRefSeq but got '. ref($object);
                        $self->error_message($error_message);
                        die;
                    }
                    $command = $command_class->create(
                                                      model_id => $self->model_id,
                                                      ref_seq_id => $object->ref_seq_id,
                                                  );
                } else {
                    $command = $command_class->create(
                                                      model_id => $self->model_id,
                                                      ref_seq_id => $object,
                                                  );
                }
            } elsif ($command_class->isa('Genome::Model::EventWithReadSet')) {
                if ($object->isa('Genome::InstrumentData')) {
                    my $ida = Genome::Model::InstrumentDataAssignment->get(
                                                                           model_id => $self->model_id,
                                                                           instrument_data_id => $object->id,
                                                                       );
                    unless ($ida) {
                        #This seems like duplicate logic but works best for the mock models in test case
                        my $model = $self->model;
                        ($ida) = grep { $_->instrument_data_id == $object->id} $model->instrument_data_assignments;
                        unless ($ida) {
                            $self->error_message('Failed to find InstrumentDataAssignment for instrument data '. $object->id .' and model '. $self->model_id);
                            die $self->error_message;
                        }
                    }
                    unless ($ida->first_build_id) {
                        $ida->first_build_id($self->build_id);
                    }
                    $command = $command_class->create(
                                                      instrument_data_id => $object->id,
                                                      model_id => $self->model_id,
                                                  );
                } else {
                    my $error_message = 'Expecting Genome::InstrumentData object but got '. ref($object);
                    $self->error_message($error_message);
                    die;
                }
            } elsif ($command_class->isa('Genome::Model::Event')) {
                $command = $command_class->create(
                                                  model_id => $self->model_id,
                                              );
            }
            unless ($command) {
                my $error_message = 'Problem creating subcommand for class '
                    . ' for object class '. ref($object)
                        . ' model id '. $self->model_id
                            . ': '. $command_class->error_message();
                $self->error_message($error_message);
                die;
            }
            $command->build_id($self->build_id);
            $command->prior_event_id($prior_event_id);
            $command->schedule;
            $prior_event_id = $command->id;
            push @scheduled_commands, $command;
            my $object_id;
            if (ref($object)) {
                $object_id = $object->id;
            } else {
                $object_id = $object;
            }
            $self->status_message('Scheduled '. $command_class .' for '. $object_id
                                  .' event_id '. $command->genome_model_event_id ."\n");
        }
    }
    return @scheduled_commands;
}

sub mail_summary {
    my $self = shift;

    my $model = $self->model;
    return unless $model->can('sequencing_platform');
    
    my $sendmail = "/usr/sbin/sendmail -t";
    my $from = "From: ssmith\@genome.wustl.edu\n";
    my $reply_to = "Reply-to: thisisafakeemail\n";
    my $subject = "Subject: Build Summary.\n";
    my $content = 'This is the Build Summary for your model '. $model->name .' and build '. $self->id ."\n";
    my $to = "To: " . $self->user_name . '@genome.wustl.edu' . "\n";

    $content .= 'https://gscweb.gsc.wustl.edu/cgi-bin/'. $model->sequencing_platform
        .'/genome-model-stage1.cgi?model-name='. $model->name  ."&refresh=1\n\n";
    if ($model->sequencing_platform eq 'solexa') {
        $content .= 'https://gscweb.gsc.wustl.edu/cgi-bin/'. $model->sequencing_platform
            .'/genome-model-stage2.cgi?model-name=' . $model->name  ."&refresh=1\n";
    }

    open(SENDMAIL, "|$sendmail") or die "Cannot open $sendmail: $!";
    print SENDMAIL $reply_to;
    print SENDMAIL $from;
    print SENDMAIL $subject;
    print SENDMAIL $to;
    print SENDMAIL $content;
    close(SENDMAIL);
    return 1;
}

sub get_all_objects {
    my $self = shift;
    #TODO: child events no longer works
    my @events = $self->child_events;
    @events = sort {$b->id cmp $a->id} @events;
    my @objects = $self->SUPER::get_all_objects;
    return (@events, @objects);
}

sub abandon {
    my $self = shift;
    my $build = $self->build;
    my @events = sort { $a->genome_model_event_id <=> $b->genome_model_event_id }
        grep { $_->genome_model_event_id ne $self->genome_model_event_id } $build->events;
    for my $event (@events) {
        unless ($event->abandon) {
            $self->error_message('Failed to abandon event with id '. $event->id);
            return;
        }
    }
    return $self->SUPER::abandon;
}


package Genome::Model::Command::Build::AbstractBaseTest;

class Genome::Model::Command::Build::AbstractBaseTest {
    is => 'Genome::Model::Command::Build',
};

package Genome::Model::Command::Build::AbstractBaseTest::StageOneJobOne;

class Genome::Model::Command::Build::AbstractBaseTest::StageOneJobOne {
    is => 'Genome::Model::EventWithReadSet',
};

sub verify_successful_completion {
    return 1;
}

package Genome::Model::Command::Build::AbstractBaseTest::StageOneJobTwo;

class Genome::Model::Command::Build::AbstractBaseTest::StageOneJobTwo {
    is => 'Genome::Model::EventWithReadSet',
};

sub verify_successful_completion {
    return 0;
}

package Genome::Model::Command::Build::AbstractBaseTest::StageOneJobThree;

class Genome::Model::Command::Build::AbstractBaseTest::StageOneJobThree {
    is => 'Genome::Model::EventWithReadSet',
};

package Genome::Model::Command::Build::AbstractBaseTest::StageTwoJobOne;

class Genome::Model::Command::Build::AbstractBaseTest::StageTwoJobOne {
    is => 'Genome::Model::EventWithRefSeq',
};

package Genome::Model::Command::Build::AbstractBaseTest::StageTwoJobTwo;

class Genome::Model::Command::Build::AbstractBaseTest::StageTwoJobTwo {
    is => 'Genome::Model::EventWithRefSeq',
};

1;

