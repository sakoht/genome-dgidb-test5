package Genome::Model::Command::AddReads::Test;

use strict;
use warnings;
use Carp;

use Genome;
use Genome::Model::Tools::Maq::CLinkage0_6_5;
use Genome::Model::Tools::Maq::MapSplit;
use Genome::RunChunk;

use GSCApp;
App::DB->db_access_level('rw');
App::DB::TableRow->use_dummy_autogenerated_ids(1);
App::DBI->no_commit(1);
App->init;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

use File::Path;
use Test::More;

sub new {
    my $class = shift;
    my %args = @_;
    my $self = bless {}, $class;

    $self->{_model_name} = $args{model_name} ||
        confess("Must define model_name for test:  $!");
    $self->{_sample_name} = $args{sample_name} ||
        confess("Must define sample_name for test:  $!");
    $self->{_processing_profile_name} = $args{processing_profile_name} ||
        confess("Must define processing_profile_name for test:  $!");
    if ($args{read_sets}) {
        my $read_sets = $args{read_sets};
        if (ref($read_sets) eq 'ARRAY') {
            $self->{_read_set_array_ref} = $read_sets;
        } else {
            confess('Supplied object type is '. ref($read_sets) ." and expected array ref:  $!");
        }
    } else {
        confess("Must define read_sets for test:  $!");
    }
    return $self;
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
        unless(ref($object) =~ /^Genome::Model/) {
            confess('expected Genome::Model* and got '. ref($object) ." object:  $!");
        }
        $self->{_model} = $object;
    }
    return $self->{_model};
}

sub runtests {
    my $self = shift;

    my @tests = (
                 'startup',
                 'create_model',
                 'add_reads',
                 'remove_data',
             );
    for my $test (@tests) {
        $self->$test;
    }
    return 1;
}

sub startup {
    is(App::DB->db_access_level,'rw','App::DB db_access_level');
    ok(App::DB::TableRow->use_dummy_autogenerated_ids,'App::DB::TableRow use_dummy_autogenerated_ids');
    ok(App::DBI->no_commit,'App::DBI no_commit');
    ok($ENV{UR_DBI_NO_COMMIT},'environment variable UR_DBI_NO_COMMIT');
    ok($ENV{UR_USE_DUMMY_AUTOGENERATED_IDS},'environment variable UR_USE_DUMMY_AUTOGENERATED_IDS');
}


sub create_model {
    my $self = shift;
    
    my $create_command= Genome::Model::Command::Create::Model->create(
                                                                      model_name => $self->{_model_name},
                                                                      sample => $self->{_sample_name},
                                                                      processing_profile_name => $self->{_processing_profile_name},
                                                                      bare_args => [],
                                                                  );

    isa_ok($create_command,'Genome::Model::Command::Create::Model');
    my $result = $create_command->execute();
    ok($result, 'execute genome-model create');
    my $genome_model_id = $result->id;
    #UR::Context->_sync_databases();

    my @models = Genome::Model->get($genome_model_id);
    is(scalar(@models),1,'expected one model');
    my $model = $models[0];
    $model->test(1);

    isa_ok($model,'Genome::Model');
    is($model->genome_model_id,$genome_model_id,'genome_model_id accessor');

    $self->add_directory_to_remove($model->data_directory);
    $self->{_model} = $model;

    my @add_reads_commands = Genome::Model::Command::AddReads->get_sub_command_classes;

    # The number of ref_seqs is hard coded, there is probably a better way to look this up
    my $ref_seqs;
    if ($model->sequencing_platform eq '454') {
        $ref_seqs = 1;
    } elsif ($model->sequencing_platform eq 'solexa') {
        $ref_seqs = 3;
    } else {
        confess('Platform '. $model->sequencing_platform .' is not supported by test');
    }

    my @sub_command_classes = Genome::Model::Command::Build::ReferenceAlignment->subordinate_job_classes;
    my $sub_command_count = 0;
    for my $command_classes (@sub_command_classes) {
        for my $command_class (@{$command_classes}) {
            $sub_command_count++;
        }
    }
    $self->{_expected_postprocess_events} = $ref_seqs * $sub_command_count;

    my @read_sets = @{$self->{_read_set_array_ref}};
    $self->{_expected_add_reads_events} = scalar(@add_reads_commands);
    # At some point the number of expected tests from test_c should be set
    # This number will vary depending on platform(some tests are not performed for 454, yet)
    #$self->num_method_tests('test_c',$);
}

sub add_reads {
    my $self = shift;
    my $model = $self->{_model};
    isa_ok($model,'Genome::Model');
    my @read_sets = @{$self->{_read_set_array_ref}};
    for my $read_set (@read_sets) {
        isa_ok($read_set,'GSC::Sequence::Item');
        my $add_reads_command = Genome::Model::Command::AddReads->create(
                                                                         model_id => $model->id,
                                                                         read_set_id => $read_set->seq_id,
                                                                     );
        isa_ok($add_reads_command,'Genome::Model::Command::AddReads');
        ok($add_reads_command->execute(),'execute genome-model add-reads');
        #UR::Context->_sync_databases();

        my @add_reads_events = Genome::Model::Event->get(
                                                         model_id => $model->id,
                                                         parent_event_id => $add_reads_command->id,
                                                     );
        is(scalar(@add_reads_events),$self->{_expected_add_reads_events},'get scheduled add_reads genome_model_events');
        # sort by event id to ensure order of events matches pipeline order
        @add_reads_events = sort {$b->genome_model_event_id <=> $a->genome_model_event_id} @add_reads_events;

        my $assign_run_command = $add_reads_events[0];
        isa_ok($assign_run_command,'Genome::Model::Command::AddReads::AssignRun');

        my $data_directory = $assign_run_command->model->data_directory;
        is($data_directory,$model->data_directory,"assign run data directory matches model");
        ok(-d $data_directory, "data directory '$data_directory' exists");

        $self->execute_event_test($assign_run_command,$read_set);

        ###RUN ALIGN-READS VIA BSUBHELPER(?). 
        my $align_reads_command = $add_reads_events[1];
        isa_ok($align_reads_command,'Genome::Model::Command::AddReads::AlignReads');

        if ($model->sequencing_platform eq 'solexa') {
            my $align_reads_ref_seq_file =  $align_reads_command->model->reference_sequence_path . "/all_sequences.bfa";
            #If the files are binary then the size of an empty file is greater than zero(20?)
            ok(-s $align_reads_ref_seq_file, 'align-reads reference sequence file exists with non-zero size');
        }

        $self->execute_event_test($align_reads_command,$read_set);

        #TODO: TEST THE RESULT OF ALIGN READS
        #Compare the map file to the test data

        my $proc_low_qual_command = $add_reads_events[2];
        isa_ok($proc_low_qual_command,'Genome::Model::Command::AddReads::ProcessLowQualityAlignments');
        $self->execute_event_test($proc_low_qual_command,$read_set);

        #$my $accept_reads_command = $add_reads_events[3];
        #isa_ok($accept_reads_command,'Genome::Model::Command::AddReads::AcceptReads');
        #$self->execute_event_test($accept_reads_command,$read_set);
    }

    my $pp_alignments = Genome::Model::Command::Build::ReferenceAlignment->create(
                                                                                        model_id => $model->id,
                                                                                    );
    isa_ok($pp_alignments,'Genome::Model::Command::Build::ReferenceAlignment');
    ok($pp_alignments->execute(), 'execute genome-model add-reads postprocess-alignments');
    #UR::Context->_sync_databases();

    my @pp_events = Genome::Model::Event->get(
                                              model_id => $model->id,
                                              parent_event_id => $pp_alignments->id,
                                          );

    is(scalar(@pp_events),$self->{_expected_postprocess_events},'get scheduled genome_model add-reads postprocess-alignments');
    # sort by event id to ensure order of events matches pipeline order
    @pp_events = sort {$b->genome_model_event_id <=> $a->genome_model_event_id} @pp_events;
print "@pp_events\n";
    my $merge_alignments_command = $pp_events[0];
    isa_ok($merge_alignments_command,'Genome::Model::Command::AddReads::MergeAlignments');
    $self->execute_event_test($merge_alignments_command);

    my $update_genotype_command = $pp_events[1];
    isa_ok($update_genotype_command,'Genome::Model::Command::AddReads::UpdateGenotype');
    $self->execute_event_test($update_genotype_command);

    my $find_variations_command = $pp_events[2];
    isa_ok($find_variations_command,'Genome::Model::Command::AddReads::FindVariations');
    $self->execute_event_test($find_variations_command);

    ###HERES THE UNLOCK MAGIC...ARE YOU READY?
    rmtree $model->lock_directory;

    my $pp_variations_command = $pp_events[3];
    isa_ok($pp_variations_command,'Genome::Model::Command::AddReads::PostprocessVariations');
    $self->execute_event_test($pp_variations_command);

    if ($model->sequencing_platform eq 'solexa') {

        my $annotate_variations_command = $pp_events[4];
        isa_ok($annotate_variations_command,'Genome::Model::Command::AddReads::AnnotateVariations');
        $self->execute_event_test($annotate_variations_command);

        #my $filter_variations_command = $pp_events[5];
        #isa_ok($filter_variations_command,'Genome::Model::Command::AddReads::FilterVariations');
        #$self->execute_event_test($filter_variations_command);
    }

    #my $upload_database_command = $pp_events[6];

    ##NOTES-------------
    ## I desire cookies...please bring cookies now.
    return 1;
}

sub execute_event_test  {
    my ($self,$event,$read_set) = @_;

    my $event_model = $event->model;
    $event_model->test(1);
    is($self->{_model}->id,$event_model->id,'genome-model id comparison');

    # Not working for EventWithReadSet
    if (defined $event->run_id) {
        my $read_set = $event->read_set;
        isa_ok($read_set,'Genome::RunChunk');
        is($read_set->seq_id,$read_set->seq_id,'genome-model read_set_id => sls seq_id ');
    }

    my $result = $event->execute();
    ok($result,'Execute: '. $event->command_name);
    if ($result) {
        set_event_status($event,'Succeeded');
    }
    else {
        diag("FAILED " . $event->command_name . " " . $event->error_message());
        set_event_status($event,'Failed');
    }

    #TODO: Write a verify_successful_completion method in all events
    #ok($event->verify_successful_completion,'Verify: '. $event->command_name)

    #UR::Context->_sync_databases();
}

sub set_event_status {
    my ($event,$status) = @_;
    my $now = UR::Time->now;
    $event->event_status($status);
    $event->date_completed($now);
}

sub remove_data {
    my $self = shift;
    my $directories_to_remove = $self->{_dir_array_ref};
    for my $directory_to_remove (@$directories_to_remove) {
        print $directory_to_remove . "\n";
        rmtree $directory_to_remove;
    }
}


sub create_test_pp {
    my $self = shift;

    my %processing_profile = @_;
    $processing_profile{bare_args} = [];
    my $create_pp_command = Genome::Model::Command::Create::ProcessingProfile::ReferenceAlignment->create(%processing_profile);
    unless($create_pp_command->execute()) {
        confess("Failed to create processing_profile for test:  $!");
    }
    #UR::Context->_sync_databases();
    return 1;
}

1;
