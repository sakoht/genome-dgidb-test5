package Genome::Model::Build;

use strict;
use warnings;

use Genome;

use Carp;
use Data::Dumper 'Dumper';
use File::Path;
use Regexp::Common;
use Workflow;
use YAML;

class Genome::Model::Build {
    type_name => 'genome model build',
    table_name => 'GENOME_MODEL_BUILD',
    is_abstract => 1,
    subclassify_by => 'subclass_name',
    id_by => [
        build_id => { is => 'NUMBER', len => 10 },
    ],
    has => [
        subclass_name           => { is => 'VARCHAR2', len => 255, is_mutable => 0, column_name => 'SUBCLASS_NAME',
                                     calculate_from => ['model_id'],
                                     # We subclass via our model's type_name (which is via it's processing profile's type_name)
                                     calculate => sub {
                                                      my($model_id) = @_;
                                                      return unless $model_id;
                                                      my $model = Genome::Model->get($model_id);
                                                      Carp::croak("Can't find Genome::Model with ID $model_id while resolving subclass for Build") unless $model;
                                                      return __PACKAGE__ . '::' . Genome::Utility::Text::string_to_camel_case($model->type_name);
                                                  }
                                   },
        data_directory          => { is => 'VARCHAR2', len => 1000, is_optional => 1 },
        model                   => { is => 'Genome::Model', id_by => 'model_id' },
        model_id                => { is => 'NUMBER', len => 10, implied_by => 'model', constraint_name => 'GMB_GMM_FK' },
        model_name              => { via => 'model', to => 'name' },
        type_name               => { via => 'model' },
        subject_id              => { via => 'model' },
        subject_name            => { via => 'model' },
        processing_profile      => { via => 'model' },
        processing_profile_name => { via => 'model' },
        the_events              => { is => 'Genome::Model::Event', reverse_as => 'build', is_many => 1 },
        the_events_statuses     => { via => 'the_events', to => 'event_status' },
        the_master_event        => { is => 'Genome::Model::Event', via => 'the_events', to => '-filter', reverse_as => 'build', where => [ event_type => 'genome model build' ] },
        run_by                  => { via => 'the_master_event', to => 'user_name' },
        status                  => { via => 'the_master_event', to => 'event_status', is_mutable => 1 },
        master_event_status     => { via => 'the_master_event', to => 'event_status' },
    ],
    has_optional => [
        disk_allocation   => { is => 'Genome::Disk::Allocation', calculate_from => [ 'class', 'id' ],
                               calculate => q(
                                    my $disk_allocation = Genome::Disk::Allocation->get(
                                                          owner_class_name => $class,
                                                          owner_id => $id,
                                                      );
                                    return $disk_allocation;
                                ) },
        software_revision => { is => 'VARCHAR2', len => 1000 },
    ],
    has_many_optional => [
        inputs           => { is => 'Genome::Model::Build::Input', reverse_as => 'build', 
                              doc => 'Inputs assigned to the model when the build was created.' },
        instrument_data  => { is => 'Genome::InstrumentData', via => 'inputs', to => 'value', is_mutable => 1, where => [ name => 'instrument_data' ], 
                              doc => 'Instrument data assigned to the model when the build was created.' },
        from_build_links => { is => 'Genome::Model::Build::Link', reverse_as => 'to_build', 
                              doc => 'bridge table entries where this is the \"to\" build(used to retrieve builds this build is \"from\")' },
        from_builds      => { is => 'Genome::Model::Build', via => 'from_build_links', to => 'from_build', 
                              doc => 'Genome builds that contribute \"to\" this build' },
        to_build_links   => { is => 'Genome::Model::Build::Link', reverse_as => 'from_build', 
                              doc => 'bridge entries where this is the \"from\" build(used to retrieve builds builds this build is \"to\")' },
        to_builds        => { is => 'Genome::Model::Build', via => 'to_build_links', to => 'to_build', 
                              doc => 'Genome builds this build contributes \"to\"' },
        attributes       => { is => 'Genome::MiscAttribute', reverse_as => '_build', where => [ entity_class_name => 'Genome::Model::Build' ] },
        metrics          => { is => 'Genome::Model::Metric', reverse_as => 'build', 
                              doc => 'Build metrics' },
        variants         => { is => 'Genome::Model::BuildVariant', reverse_as => 'build', 
                              doc => 'variants linked to this build... currently only for Somatic builds but need this accessor for get_all_objects' },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

sub __display_name__ {
    my $self = shift;
    return $self->id . ' of ' . $self->model->name;
}

# TODO: Replace this with get_class_param
use Genome::Command::Base;
*from_cmdline = \&Genome::Command::Base::default_cmdline_selector;

sub _resolve_subclass_name_by_sequencing_platform { # only temporary, subclass will soon be stored
    my $class = shift;

    Carp::confess("this is used by sub-classes which further subclassify by sequencing platform!")
        if $class eq __PACKAGE__;

    my $sequencing_platform;
    if (ref($_[0]) and $_[0]->isa('Genome::Model::Build')) {
        $sequencing_platform = $_[0]->model->sequencing_platform;
    } 
    else {
        my %params;
        if (ref($_[0]) and $_[0]->isa("UR::BoolExpr")) {
            %params = $_[0]->params_list;
        }
        else {
            %params = @_;
        }
        my $model_id = $params{model_id};
        $class->_validate_model_id($params{model_id})
            or return;
        my $model = Genome::Model->get($params{model_id});
        unless ( $model ) {
            Carp::confess("Can't get model for id: .".$params{model_id});
        }
        $sequencing_platform = $model->sequencing_platform;
    }

    return unless $sequencing_platform;

    return $class. '::'.Genome::Utility::Text::string_to_camel_case($sequencing_platform);
}

sub _resolve_subclass_name_by_assembler_name { # only temporary, subclass will soon be stored
    my $class = shift;

    Carp::confess("this is used by sub-classes which further subclassify by sequencing platform!")
        if $class eq __PACKAGE__;

    my $assembler_name;
    if (ref($_[0]) and $_[0]->isa('Genome::Model::Build')) {
        $assembler_name = $_[0]->model->assembler_name;
    } 
    else {
        my %params;
        if (ref($_[0]) and $_[0]->isa("UR::BoolExpr")) {
            %params = $_[0]->params_list;
        }
        else {
            %params = @_;
        }
        my $model_id = $params{model_id};
        $class->_validate_model_id($params{model_id})
            or return;
        my $model = Genome::Model->get($params{model_id});
        unless ( $model ) {
            Carp::confess("Can't get model for id: .".$params{model_id});
        }
        $assembler_name = $model->assembler_name;
    }

    return unless $assembler_name;

    return $class. '::'.Genome::Utility::Text::string_to_camel_case($assembler_name);
}

# auto generate sub-classes for any valid processing profile
sub __extend_namespace__ {
    my ($self,$ext) = @_;

    my $meta = $self->SUPER::__extend_namespace__($ext);
    return $meta if $meta;
    
    my $pp_subclass_name = 'Genome::ProcessingProfile::' . $ext;
    my $pp_subclass_meta = UR::Object::Type->get($pp_subclass_name);
    if ($pp_subclass_meta and $pp_subclass_name->isa('Genome::ProcessingProfile')) {
        my $build_subclass_name = 'Genome::Model::Build::' . $ext;
        my $build_subclass_meta = UR::Object::Type->define(
            class_name => $build_subclass_name,
            is => 'Genome::Model::Build',
        );
        die "Error defining $build_subclass_name for $pp_subclass_name!" unless $build_subclass_meta;
        return $build_subclass_meta;
    }
    return;
}

sub create {
    my $class = shift;
    if ($class eq __PACKAGE__ or $class->__meta__->is_abstract) {
        # let the base class re-call the constructor from the correct sub-class
        return $class->SUPER::create(@_);
    }

    my $bx = $class->define_boolexpr(@_);
    my $model_id = $bx->value_for('model_id');

    # model
    unless ( $class->_validate_model_id($model_id) ) {
        return;
    }

    #unless ($bx->value_for('subclass_name')) {
    #    $bx = $bx->add_filter(subclass_name => $class);
    #}

    # create
    my $self = $class->SUPER::create($bx);
    return unless $self;

    # instrument data assignments - set first build id
    my @ida = $self->model->instrument_data_assignments;
    for my $ida ( @ida ) {
        next if defined $ida->first_build_id;
        $ida->first_build_id( $self->id )
    }
    
    # inputs
    unless ( $self->_copy_model_inputs ) {
        $self->delete;
        return;
    }

    # data directory
    unless ($self->data_directory) {
        my $dir;
        eval {
            $dir = $self->resolve_data_directory;
        };
        if ($@) {
            $self->error_message("Failed to resolve a data directory for a new build!: $@");
            $self->delete;
            return;
        }
        $self->data_directory($dir);
    }

    my $processing_profile = $self->processing_profile;
    unless ($processing_profile->_initialize_build($self)) {
        $class->error_message($processing_profile->error_message);
        $self->delete;
        return;
    }

    return $self;
}

sub _validate_model_id {
    my ($class, $model_id) = @_;

    unless ( defined $model_id ) {
        $class->error_message("No model id given to get model of build.");
        return;
    }

    unless ( $model_id =~ /^$RE{num}{int}$/ ) {
        $class->error_message("Model id ($model_id) is not an integer.");
        return;
    }

    unless ( Genome::Model->get($model_id) ) {
        $class->error_message("Can't get model for id ($model_id).");
        return;
    }
    
    return 1;
}

sub _copy_model_inputs {
    my $self = shift;

    # Create gets called twice, calling this method twice, so
    #  gotta check if we added the inputs already (and crashes). 
    #  I tried to figure out how to stop create being called twice, but could not.
    my @inputs = $self->inputs;
    return 1 if @inputs;

    for my $input ( $self->model->inputs ) {
        my %params = map { $_ => $input->$_ } (qw/ name value_class_name value_id /);
        unless ( $self->add_input(%params) ) {
            $self->error_message("Can't copy model input to build: ".Data::Dumper::Dumper(\%params));
            return;
        }
    }

    # FIXME temporary - copy model instrument data as inputs, when all 
    #  inst_data is an input, this can be removed
    my @existing_inst_data = $self->instrument_data;
    my @model_inst_data = $self->model->instrument_data;
    for my $inst_data ( @model_inst_data ) {
        # We may have added the inst data when adding the inputs
        # Adding as input cuz of mock inst data
        #print Data::Dumper::Dumper($inst_data);
        next if grep { $inst_data->id eq $_->id } @existing_inst_data;
        my %params = (
            name => 'instrument_data',
            value_class_name => $inst_data->class,
            value_id => $inst_data->id,
        );
        unless ( $self->add_input(%params) ) {
            $self->error_message("Can't add instrument data (".$inst_data->id.") to build.");
            return;
        }
    }

    return 1;

}

sub instrument_data_assignments {
    my $self = shift;
    my @idas = Genome::Model::InstrumentDataAssignment->get(
        model_id => $self->model_id,
        first_build_id => {
            operator => '<=',
            value => $self->build_id,
        },
    );
    return @idas;
}

sub instrument_data_count {
    my $self = shift;

    # Try inst data from inputs
    my @instrument_data = $self->instrument_data;
    if ( @instrument_data ) {
        return scalar(@instrument_data);
    }

    # use first build id on model's ida for older builds
    return scalar( $self->instrument_data_assignments );
}

sub events {
    my $self = shift;
    my @events = Genome::Model::Event->get(
        model_id => $self->model_id,
        build_id => $self->build_id,
    );
    return @events;
}

sub build_events {
    my $self = shift;
    my @build_events = Genome::Model::Event::Build->get(
        model_id => $self->model_id,
        build_id => $self->build_id,
    );
    return @build_events;
}

sub build_event {
    my $self = shift;
    my @build_events = $self->build_events;
    if (scalar(@build_events) > 1) {
        my $error_message = 'Found '. scalar(@build_events) .' build events for model id '.
        $self->model_id .' and build id '. $self->build_id ."\n";
        for (@build_events) {
            $error_message .= "\t". $_->desc .' '. $_->event_status ."\n";
        }
        die($error_message);
    }
    return $build_events[0];
}

sub workflow_instances {
    my $self = shift;
    my @instances = Workflow::Operation::Instance->get(
        name => $self->build_id . ' all stages'
    );
    return @instances;
}

sub newest_workflow_instance {
    my $self = shift;
    my @sorted = sort { 
        $b->id <=> $a->id
    } $self->workflow_instances;
    if (@sorted) { 
        return $sorted[0];
    } else {
        return;
    }
}

sub build_status {
    my $self = shift;
    my $build_event = $self->build_event;
    unless ($build_event) {
        return;
    }
    return $build_event->event_status;
}

sub date_scheduled {
    my $self = shift;
    my $build_event = $self->build_event;
    unless ($build_event) {
        return;
    }
    return $build_event->date_scheduled;
}

sub date_completed {
    my $self = shift;
    my $build_event = $self->build_event;
    unless ($build_event) {
        return;
    }
    return $build_event->date_completed;
}

sub calculate_estimated_kb_usage {
    my $self = shift;

    # Default of 500 MiB in case a subclass fails to
    # override this method.  At least this way there
    # will be an allocation, which will likely be
    # wildly inaccurate, but if the build fails to fail,
    # when it finishes, it will reallocate down to the
    # actual size.  Whereas the previous behaviour 
    # (return undef) caused *no* allocation to be made.
    # Which it has been decided is a bigger problem.
    return 512_000;
}

# If the data directory is not set, resolving it requires making an allocation.  A build is unlikely to
# make a new allocation at any other time, so a separate build instance method for allocating is not
# provided.
sub resolve_data_directory {
    my $self = shift;
    my $model = $self->model;
    my $build_data_directory;
    my $model_data_directory = $model->data_directory;
    my $model_path_is_abnormal = defined($model_data_directory) && $model_data_directory !~ /\/gscmnt\/.*\/info\/(?:medseq\/)?.*/;

    if($model->genome_model_id < 0 && $model_path_is_abnormal)
    {
        # The build is being created for an automated test; allocating for it would leave stray directories.
        # Rather than relying on this if statement, tests should specify a build directory.
        $build_data_directory = $model_data_directory . '/build' . $self->id;
        warn "Please update this test to set build data_directory. (generated data_directory: \"$build_data_directory\")";
        unless (Genome::Utility::FileSystem->create_directory($build_data_directory)) {
            $self->error_message("Failed to create directory '$build_data_directory'");
            die $self->error_message;
        }
    }
    else
    {
        if ($model_path_is_abnormal) {
            # why should this ever fail?
            warn "The model data directory \"$model_data_directory\" follows an unexpected pattern!";
        }
    
        my $allocation_path = 'model_data/' . $model->id . '/build'. $self->build_id;
        my $kb_requested = $self->calculate_estimated_kb_usage;
        unless ($kb_requested) {
            warn "No disk allocation for this build.";
            return;
        }
    
        my $disk_group_name = $model->processing_profile->_resolve_disk_group_name_for_build($self);
        unless ($disk_group_name) {
            die $self->error_message('Failed to resolve a disk group for a new build!');
        }
    
        my $disk_allocation = Genome::Disk::Allocation->allocate(disk_group_name => $disk_group_name,
                                                                 allocation_path => $allocation_path,
                                                                 kilobytes_requested => $kb_requested,
                                                                 owner_class_name => $self->class,
                                                                 owner_id => $self->id);
        unless ($disk_allocation) {
            die $self->error_message('Failed to get disk allocation');
        }
    
        $build_data_directory = $disk_allocation->absolute_path;
        Genome::Utility::FileSystem->validate_existing_directory($build_data_directory);
    
        # TODO: we should stop having model directories and making build symlinks!!!
        my $build_symlink = $model_data_directory . '/build' . $self->build_id;
        unlink $build_symlink if -e $build_symlink;
        unless (Genome::Utility::FileSystem->create_symlink($build_data_directory,$build_symlink)) {
            $self->error_message("Failed to make symlink \"$build_symlink\" with target \"$build_data_directory\"");
            die $self->error_message;
        }
    }

    return $build_data_directory;
}

sub reallocate {
    my $self = shift;

    my $disk_allocation = $self->disk_allocation
        or return 1; # ok - may not have an allocation

    unless ($disk_allocation->reallocate) {
        $self->warning_message('Failed to reallocate disk space.');
    }

    return 1;
}

sub log_directory { 
    return  $_[0]->data_directory . '/logs/';
}

sub reports_directory { 
    return  $_[0]->data_directory . '/reports/';
}

sub resolve_reports_directory { return reports_directory(@_); } #????

sub add_report {
    my ($self, $report) = @_;

    my $directory = $self->resolve_reports_directory;
    if (-d $directory) {
        my $subdir = $directory . '/' . $report->name_to_subdirectory($report->name);
        if (-e $subdir) {
            $self->status_message("Sub-directory $subdir exists!   Moving it out of the way...");
            my $n = 1;
            my $max = 20;
            while ($n < $max and -e $subdir . '.' . $n) {
                $n++;
            }
            if ($n == $max) {
                die "Too many re-runs of this report!  Contact Informatics..."
            }
            rename $subdir, "$subdir.$n";
            if (-e $subdir) {
                die "failed to move old report dir $subdir to $subdir.$n!: $!";
            }
        }
    }
    else {
        $self->status_message("creating directory $directory...");
        unless (Genome::Utility::FileSystem->create_directory($directory)) {
            die "failed to make directory $directory!: $!";
        }
    }
    
    if ($report->save($directory)) {
        $self->status_message("Saved report to override directory: $directory");
        return 1;
    }
    else {
        $self->error_message("Error saving report!: " . $report->error_message());
        return;
    }
}

sub start {
    my $self = shift;
    my %params = @_;

    # TODO make it so we don't need to pass anything to init the workflow.
    my $workflow = $self->_initialize_workflow($params{job_dispatch} || 'apipe');
    unless ($workflow) {
        my $msg = $self->error_message("Failed to initialize a workflow!");
        croak $msg;
    }

#    $params{workflow} = $workflow;
    
    return $self->_launch(%params);
}

sub restart {
    my $self = shift;
    my %params = @_;
   
    if (delete $params{job_dispatch}) {
        cluck $self->error_message('job_dispatch cannot be changed on restart');
    }
    
    if ($self->run_by ne $ENV{USER}) {
        croak $self->error_message("Can't restart a build originally started by: " . $self->run_by);
    }

    my $xmlfile = $self->data_directory . '/build.xml';
    if (!-e $xmlfile) {
        croak $self->error_message("Can't find xml file for build (" . $self->id . "): " . $xmlfile);
    }

    my $loc_file = $self->data_directory . '/server_location.txt';
    if (-e $loc_file) {
        croak $self->error_message("Server location file in build data directory exists. Cannot restart");
    }

    my $w = $self->newest_workflow_instance;
    if ($w && !$params{fresh_workflow}) {
        if ($w->is_done) {
            croak $self->error_message("Workflow Instance is complete");
        }
    }

    my $build_event = $self->build_event;
    $build_event->event_status('Scheduled');
    $build_event->date_completed(undef);
    
    return $self->_launch(%params);
}

sub _launch {
    my $self = shift;
    my %params = @_;

    # right now it is "inline" or the name of an LSF queue.
    # ultimately, it will be the specification for parallelization
    #  including whether the server is inline, forked, or bsubbed, and the
    #  jobs are inline, forked or bsubbed from the server
    my $server_dispatch = delete $params{server_dispatch} || 'inline';
    my $job_dispatch = delete $params{job_dispatch} || 'inline';
    my $fresh_workflow = delete $params{fresh_workflow};

    my $job_group_spec;
    if (exists $params{job_group}) {
        my $job_group = delete $params{job_group};
        if ($job_group) {
            $job_group_spec = " -g $job_group";
        }
        else {
            $job_group_spec = "";
        }
    }
    else {
        $job_group_spec = ' -g /build/' . $ENV{USER};
    }

    die "Bad params!  Expected server_dispatch and job_dispatch!" . Data::Dumper::Dumper(\%params) if %params;

    my $model = $self->model;
    my $build_event = $self->the_master_event;

    # TODO: send the workflow to the dispatcher instead of having LSF logic here.
    if ($server_dispatch eq 'inline') {
        # TODO: redirect STDOUT/STDERR to these files
        #$build_event->output_log_file,
        #$build_event->error_log_file,
        
        my %args = (
            model_id => $self->model_id,
            build_id => $self->id,
        );
        if ($job_dispatch eq 'inline') {
            $args{inline} = 1;
        }
        
        my $rv = Genome::Model::Command::Services::Build::Run->execute(%args);
        return $rv;
    }
    else {
        my $add_args = ($job_dispatch eq 'inline') ? ' --inline' : '';
        if ($fresh_workflow) {
            $add_args .= ' --restart';
        }

	my $host_group = '';
	if ($server_dispatch ne 'workflow') {
            $host_group = '-m blades';
	}
 
        # bsub into the queue specified by the dispatch spec
        my $lsf_command = sprintf(
            'bsub -N -H -q %s %s %s -u %s@genome.wustl.edu -o %s -e %s annotate-log genome model services build run%s --model-id %s --build-id %s',
            $server_dispatch, ## lsf queue
            $host_group,
            $job_group_spec,
            $ENV{USER}, 
            $build_event->output_log_file,
            $build_event->error_log_file,
            $add_args,
            $model->id,
            $self->id,
        );
        print $lsf_command."\n";
    
        my $job_id = $self->_execute_bsub_command($lsf_command)
            or return;
    
        $build_event->lsf_job_id($job_id);

        my $commit_observer;
        my $rollback_observer;
        
        $commit_observer = UR::Context->add_observer(
            aspect => 'commit',
            callback => sub {
                `bresume $job_id`;
                $commit_observer->delete;
                undef $commit_observer;
                $rollback_observer->delete;
                undef $rollback_observer;
            }
        );

        $rollback_observer = UR::Context->add_observer(
            aspect => 'rollback',
            callback => sub {
                `bkill $job_id`;
                # delete and undef observers so they don't persist
                # they should have been deleted in the rollback, 
                #  but attempt to delete again just in case
                if ( $rollback_observer ) {
                    $rollback_observer->delete unless $rollback_observer->isa('UR::DeletedRef');
                    undef $rollback_observer;
                }
                if ( $commit_observer ) {
                    $commit_observer->delete unless $commit_observer->isa('UR::DeletedRef');
                    undef $commit_observer;
                }
            }
        );

        return 1;
    }
}

sub _initialize_workflow {
    my $self = shift;
    my $lsf_queue_eliminate_me = shift || 'apipe';

    Genome::Utility::FileSystem->create_directory( $self->data_directory )
        or return;

    Genome::Utility::FileSystem->create_directory( $self->log_directory )
        or return;

    if ( my $existing_build_event = $self->build_event ) {
        $self->error_message(
            "Can't schedule this build (".$self->id."), it a already has a main build event: ".
            Data::Dumper::Dumper($existing_build_event)
        );
        return;
    }

    $self->software_revision(UR::Util::used_libs_perl5lib_prefix());

    my $build_event = Genome::Model::Event::Build->create(
        model_id => $self->model->id,
        build_id => $self->id,
        event_type => 'genome model build',
    );

    unless ( $build_event ) {
        $self->error_message( 
            sprintf("Can't create build for model (%s %s)", $self->model->id, $self->model->name) 
        );
        $self->delete;
        return;
    }

    $build_event->schedule; # in G:M:Event, sets status, times, etc.

    my $model = $self->model;
    my $processing_profile = $self->processing_profile;

    my $workflow = $processing_profile->_resolve_workflow_for_build($self,$lsf_queue_eliminate_me);

    $workflow->save_to_xml(OutputFile => $self->data_directory . '/build.xml');
    
    return $workflow;
}

sub _execute_bsub_command { # here to overload in testing
    my ($self, $cmd) = @_;

    my $bsub_output = `$cmd`;
    my $rv = $? >> 8;
    if ( $rv ) {
        $self->error_message("Failed to launch bsub (exit code: $rv) command:\n$bsub_output");
        return;
    }

    if ( $bsub_output =~ m/Job <(\d+)>/ ) {
        return "$1";
    } 
    else {
        $self->error_message("Launched busb command, but unable to parse bsub output: $bsub_output");
        return;
    }
}


sub initialize {
    my $self = shift;

    $self->_verify_build_is_not_abandoned_and_set_status_to('Running')
        or return;
   
    $self->generate_send_and_save_report('Genome::Model::Report::BuildInitialized')
        or return;

    return 1;
}

sub fail {
    my ($self, @errors) = @_;

    # reload all the events
    my @e = Genome::Model::Event->load(build_id => $self->build_id);

    $self->_verify_build_is_not_abandoned_and_set_status_to('Failed', 1)
        or return;

    # set event status
    for my $e ($self->the_events(event_status => 'Running')) {
        $e->event_status('Failed');
    }

    $self->generate_send_and_save_report(
        'Genome::Model::Report::BuildFailed', {
            errors => \@errors,
        },
    )
        or return;
    
    # FIXME Don't know if this should go here, but then we would have to call success and abandon through the model
    my $last_complete_build = $self->model->resolve_last_complete_build;
    if ( $last_complete_build and $last_complete_build->id eq $self->id ) {
        $self->error_message("Tried to resolve last complete build for model (".$self->model_id."), which should not return this build (".$self->id."), but did.");
        # FIXME soon - return here
        # return;
    }
    
    return 1;
}

sub success {
    my $self = shift;

    # reload all the events
    my @e = Genome::Model::Event->load(build_id => $self->build_id);

    # set status
    $self->_verify_build_is_not_abandoned_and_set_status_to('Succeeded', 1)
        or return;

    # set event status
    for my $e ($self->the_events(event_status => ['Running','Scheduled'])) {
        $e->event_status('Abandoned');
    }

    # report - if this fails set status back to Running, then the workflow will fail it
    unless ( $self->generate_send_and_save_report( $self->report_generator_class_for_success ) ) {
        $self->_verify_build_is_not_abandoned_and_set_status_to('Running');
        return;
    }
    
    # Launch new builds for any convergence models containing this model.
    # To prevent infinite loops, don't do this for convergence builds.
    # FIXME subclass this!
    if($self->type_name !~ /convergence/) {
        for my $model_group ($self->model->model_groups) {
            eval {
                $model_group->schedule_convergence_rebuild;
            };
            if($@) {
                $self->error_message('Could not schedule convergence build for model group ' . $model_group->id . '.  Continuing anyway.');
            }
        }
    }

    # reallocate - always returns true (legacy behavior)
    $self->reallocate; 

    # FIXME Don't know if this should go here, but then we would have to call success and abandon through the model
    my $last_complete_build = $self->model->resolve_last_complete_build;
    unless ( $last_complete_build ) {
        $self->error_message("Tried to resolve last complete build for model (".$self->model_id."), but no build was returned.");
        # FIXME soon - return here
        #return;
    }
    unless ( $last_complete_build->id eq $self->id ) {
        $self->error_message("Tried to resolve last complete build for model (".$self->model_id."), which should return this build (".$self->id."), but returned another build (".$last_complete_build->id.").");
        # FIXME soon - return here
        #return;
    }

    return 1;
}

sub _verify_build_is_not_abandoned_and_set_status_to {
    my ($self, $status, $set_date_completed) = @_;

    my $build_event = $self->build_event;
    # Do we have a master event?
    unless ( $build_event ) {
        $self->error_message(
            'Cannot set build ('.$self->id.") status to '$status' because it does not have a master event."
        );
        return;
    }

    # Is it abandoned?
    if ( $build_event->event_status eq 'Abandoned' ) {
        $self->error_message(
            'Cannot set build ('.$self->id.") status to '$status' because the master event has been abandoned."
        );
        return;
    }

    # Set status and date completed
    $build_event->event_status($status);
    $build_event->date_completed( UR::Time->now ) if $set_date_completed;

    return $build_event;
}


sub abandon {
    my $self = shift;

    # Abandon events
    $self->_abandon_events
        or return;

    # Reallocate - always returns true (legacy behavior)
    $self->reallocate;

    # FIXME Don't know if this should go here, but then we would have to call success and abandon through the model
    my $last_complete_build = $self->model->resolve_last_complete_build;
    if ( $last_complete_build and $last_complete_build->id eq $self->id ) {
        $self->error_message("Tried to resolve last complete build for model (".$self->model_id."), which should not return this build (".$self->id."), but did.");
        # FIXME soon - return here
        # return;
    }

    return 1;
}

sub _abandon_events { # does not realloc
    my $self = shift;

    my @events = sort { $b->id <=> $a->id } $self->events;
    for my $event ( @events ) {
        unless ( $event->abandon ) {
            $self->error_message(
                sprintf(
                    'Failed to abandon build (%s) because could not abandon event (%s).',
                    $self->id,
                    $event->id,
                )
            );
            return;
        }
    }

    return 1;
}

sub reports {
    my $self = shift;
    my $report_dir = $self->resolve_reports_directory;
    return unless -d $report_dir;
    return Genome::Report->create_reports_from_parent_directory($report_dir);
}

sub get_report {
    my ($self, $report_name) = @_;

    unless ( $report_name ) { # die?
        $self->error_message("No report name given to get report");
        return;
    }

    my $report_dir = $self->reports_directory.'/'.
    Genome::Report->name_to_subdirectory($report_name);
    return unless -d $report_dir;

    return Genome::Report->create_report_from_directory($report_dir); 
}

sub available_reports {
    my $self = shift;
    my $report_dir = $self->resolve_reports_directory;
    return unless -d $report_dir;
    return Genome::Report->create_reports_from_parent_directory($report_dir);
}

sub generate_send_and_save_report {
    my ($self, $generator_class, $additional_params) = @_;
    
    $additional_params ||= {};
    my $generator = $generator_class->create(
        build_id => $self->id,
        %$additional_params,
    );
    unless ( $generator ) {
        $self->error_message(
            sprintf(
                "Can't create report generator (%s) for build (%s)",
                $generator_class,
                $self->id
            )
        );
        return;
    }

    my $report = $generator->generate_report;
    unless ( $report ) {
        $self->error_message(
            sprintf("Can't generate report (%s) for build (%s)", $generator->name, $self->id)
        );
        return;
    }
    
    my $to = $self->_get_to_addressees_for_report_generator_class($generator_class)
        or return;
    
    my $email_confirmation = Genome::Report::Email->send_report(
        report => $report,
        to => $to,
        from => 'apipe@genome.wustl.edu',
        replyto => 'noreply@genome.wustl.edu',
        # maybe not the best/correct place for this information but....
        xsl_files => [ $generator->get_xsl_file_for_html ],
    );
    unless ( $email_confirmation ) {
        $self->error_message('Couldn\'t email build report ('.lc($report->name).')');
        return;
    }

    $self->add_report($report)
        or return;

    return $report;
}

sub _get_to_addressees_for_report_generator_class {
    my ($self, $generator_class) = @_;

    confess "No report generator class given to get 'to' addressees" unless $generator_class;

    my $user = $self->build_event->user_name;
    # Send reports to user unless it's apipe
    unless ( $user eq 'apipe' ) {
        return $self->build_event->user_name.'@genome.wustl.edu';
    }

    # Send failed reports to bulk
    return 'apipe-bulk@genome.wustl.edu' if $generator_class eq 'Genome::Model::Report::BuildFailed';

    # Send others to run
    return 'apipe-run@genome.wustl.edu';
}

sub report_generator_class_for_success { # in subclass replace w/ summary or the like?
    return 'Genome::Model::Report::BuildSucceeded';
}

#< SUBCLASSING >#
#
# This is called by the infrastructure to appropriately classify abstract processing profiles
# according to their type name because of the "sub_classification_method_name" setting
# in the class definiton...
sub _resolve_subclass_name {
    my $class = shift;

    my $type_name;
	if ( ref($_[0]) and $_[0]->isa(__PACKAGE__) ) {
		$type_name = $_[0]->model->type_name;
	}
    else {
        my ($bx,@extra) = $class->define_boolexpr(@_);
        my %params = ($bx->params_list, @extra);
        my $model_id = $params{model_id};
        my $model = Genome::Model->get($model_id);
        unless ($model) {
            return undef;
        }
        $type_name = $model->type_name;
    }

    unless ( $type_name ) {
        my $rule = $class->define_boolexpr(@_);
        $type_name = $rule->specified_value_for_property_name('type_name');
    }

    if (defined $type_name ) {
        my $subclass_name = $class->_resolve_subclass_name_for_type_name($type_name);
        my $sub_classification_method_name = $class->get_class_object->sub_classification_method_name;
        if ( $sub_classification_method_name ) {
            if ( $subclass_name->can($sub_classification_method_name)
                 eq $class->can($sub_classification_method_name) ) {
                return $subclass_name;
            } else {
                return $subclass_name->$sub_classification_method_name(@_);
            }
        } else {
            return $subclass_name;
        }
    } else {
        return undef;
    }
}

sub _resolve_subclass_name_for_type_name {
    my ($class,$type_name) = @_;
    my @type_parts = split(' ',$type_name);

    my @sub_parts = map { ucfirst } @type_parts;
    my $subclass = join('',@sub_parts);

    my $class_name = join('::', 'Genome::Model::Build' , $subclass);
    return $class_name;

}

sub _resolve_type_name_for_class {
    my $class = shift;

    my ($subclass) = $class =~ /^Genome::Model::Build::([\w\d]+)$/;
    return unless $subclass;

    return lc join(" ", ($subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx));

    my @words = $subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx;
    return lc(join(" ", @words));
}

sub get_all_objects {
    my $self = shift;

    my $sorter = sub { # not sure why we sort, but I put it in a anon sub for convenience
        return unless @_;
        #if ( $_[0]->id =~ /^\-/) {
            return sort {$b->id cmp $a->id} @_;
            #} 
            #else {
            #return sort {$a->id cmp $b->id} @_;
            #}
    };

    return map { $sorter->( $self->$_ ) } (qw/ events inputs metrics from_build_links to_build_links variants/);
}

sub yaml_string {
    my $self = shift;
    my $string = YAML::Dump($self);
    for my $object ($self->get_all_objects) {
        $string .= YAML::Dump($object);
    }
    return $string;
}

sub add_to_build{
    my $self = shift;
    my (%params) = @_;
    my $build = delete $params{to_build};
    my $role = delete $params{role};
    $role||='member';
   
    $self->error_message("no to_build provided!") and die unless $build;
    my $from_id = $self->id;
    my $to_id = $build->id;
    unless( $to_id and $from_id){
        $self->error_message ( "no value for this build(from_build) id: <$from_id> or to_build id: <$to_id>");
        die;
    }
    my $reverse_bridge = Genome::Model::Build::Link->get(from_build_id => $to_id, to_build_id => $from_id);
    if ($reverse_bridge){
        my $string =  "A build link already exists for these two builds, and in the opposite direction than you specified:\n";
        $string .= "to_build: ".$reverse_bridge->to_build." (this build)\n";
        $string .= "from_build: ".$reverse_bridge->from_build." (the build you are trying to set as a 'to' build for this one)\n";
        $string .= "role: ".$reverse_bridge->role;
        $self->error_message($string);
        die;
    }
    my $bridge = Genome::Model::Build::Link->get(from_build_id => $from_id, to_build_id => $to_id);
    if ($bridge){
        my $string =  "A build link already exists for these two builds:\n";
        $string .= "to_build: ".$bridge->to_build." (the build you are trying to set as a 'to' build for this one)\n";
        $string .= "from_build: ".$bridge->from_build." (this build)\n";
        $string .= "role: ".$bridge->role;
        $self->error_message($string);
        die;
    }
    $bridge = Genome::Model::Build::Link->create(from_build_id => $from_id, to_build_id => $to_id, role => $role);
    return $bridge;
}

sub add_from_build { # rename "add an underlying build" or something...
    my $self = shift;
    my (%params) = @_;
    my $build = delete $params{from_build};
    my $role = delete $params{role};
    $role||='member';
   
    $self->error_message("no from_build provided!") and die unless $build;
    my $to_id = $self->id;
    my $from_id = $build->id;
    unless( $to_id and $from_id){
        $self->error_message ( "no value for this build(to_build) id: <$to_id> or from_build id: <$from_id>");
        die;
    }
    my $reverse_bridge = Genome::Model::Build::Link->get(from_build_id => $to_id, to_build_id => $from_id);
    if ($reverse_bridge){
        my $string =  "A build link already exists for these two builds, and in the opposite direction than you specified:\n";
        $string .= "to_build: ".$reverse_bridge->to_build." (the build you are trying to set as a 'from' build for this one)\n";
        $string .= "from_build: ".$reverse_bridge->from_build." (this build)\n";
        $string .= "role: ".$reverse_bridge->role;
        $self->error_message($string);
        die;
    }
    my $bridge = Genome::Model::Build::Link->get(from_build_id => $from_id, to_build_id => $to_id);
    if ($bridge){
        my $string =  "A build link already exists for these two builds:\n";
        $string .= "to_build: ".$bridge->to_build." (this build)\n";
        $string .= "from_build: ".$bridge->from_build." (the build you are trying to set as a 'from' build for this one)\n";
        $string .= "role: ".$bridge->role;
        $self->error_message($string);
        die;
    }
    $bridge = Genome::Model::Build::Link->create(from_build_id => $from_id, to_build_id => $to_id, role => $role);
    return $bridge;
}

sub delete {
    my $self = shift;
    my %params = @_;
    my $keep_build_directory = $params{keep_build_directory};

    # Abandon
    unless ( $self->_abandon_events ) {
        $self->error_message(
            "Unable to delete build (".$self->id.") because the events could not be abandoned"
        );
        return;
    }
    
    # Delete all associated objects
    my @objects = $self->get_all_objects;
    for my $object (@objects) {
        $object->delete;
    }

    # Re-point instrument data assigned first on this build to the next build.
    my ($next_build,@subsequent_builds) = Genome::Model::Build->get(
        model_id => $self->model_id,
        id => {
            operator => '>',
            value => $self->build_id,
        },  
    );
    my $next_build_id = ($next_build ? $next_build->id : undef);
    my @idas_fix = Genome::Model::InstrumentDataAssignment->get(
        model_id => $self->model_id,
        first_build_id => $self->build_id
    );
    for my $idas (@idas_fix) {
        $idas->first_build_id($next_build_id);
    }

    if ($self->data_directory && -e $self->data_directory && !$keep_build_directory) {
        unless (rmtree($self->data_directory, { error => \my $remove_errors })) {
            if (@$remove_errors) {
                my $error_summary;
                for my $error (@$remove_errors) {
                    my ($file, $error_message) = %$error;
                    if ($file eq '') {
                        $error_summary .= "General error removing build directory: $error_message\n";
                    }
                    else {
                        $error_summary .= "Error removing file $file : $error_message\n";
                    }
                }
                $self->error_message($error_summary);
            }

            confess "Failed to remove build directory tree at " . $self->data_directory . ", cannot remove build!";
        }
    }
    my $disk_allocation = $self->disk_allocation;
    if ($disk_allocation && !$keep_build_directory) {
        unless ($disk_allocation->deallocate) {
             $self->warning_message('Failed to deallocate disk space.');
        }
    }
    
    # FIXME Don't know if this should go here, but then we would have to call success and abandon through the model
    #  This works b/c the events are deleted prior to this call, so the model doesn't think this is a completed
    #  build
    my $last_complete_build = $self->model->resolve_last_complete_build;
    if ( $last_complete_build and $last_complete_build->id eq $self->id ) {
        $self->error_message("Tried to resolve last complete build for model (".$self->model_id."), which should not return this build (".$self->id."), but did.");
        # FIXME soon - return here
        # return;
    }

    return $self->SUPER::delete;
}

sub set_metric {
    my $self = shift;
    my $metric_name  = shift;
    my $metric_value = shift;

    my $metric = Genome::Model::Metric->get(build_id=>$self->id, name=>$metric_name);
    my $new_metric;
    if ($metric) {
        #delete an existing one and create the new one
        $metric->delete;
        $new_metric = Genome::Model::Metric->create(build_id=>$self->id, name=>$metric_name, value=>$metric_value);
    } else {
        $new_metric = Genome::Model::Metric->create(build_id=>$self->id, name=>$metric_name, value=>$metric_value);
    }
    
    return $new_metric->value;
}

sub get_metric {
    my $self = shift;
    my $metric_name = shift;

    my $metric = Genome::Model::Metric->get(build_id=>$self->id, name=>$metric_name);
    if ($metric) {
        return $metric->value;
    }
}

# why hide this here? -ss
package Genome::Model::Build::AbstractBaseTest;

class Genome::Model::Build::AbstractBaseTest {
    is => 'Genome::Model::Build',
};

1;
