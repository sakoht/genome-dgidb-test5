package Genome::Sys::Command::Search::Index;

use Genome;

class Genome::Sys::Command::Search::Index {
    is => ['Genome::Role::Logger', 'Command'],
    has => [
        action => {
            is => 'Text',
            default => 'add',
            valid_values => ['add', 'delete'],
        },
        subject_text => {
            is => 'Text',
            shell_args_position => 1,
        },
        confirm => {
            is => 'Boolean',
            default => 1,
        },
        max_changes_per_commit => {
            is => 'Number',
            default => 50,
        },
        loop_sleep => {
            is => 'Number',
            default => 10,
        },
    ],
};

sub execute {
    my $self = shift;

    if ($self->subject_text ne 'list') {
        my $confirmed = $self->prompt_for_confirmation() if $self->confirm;
        if ($self->confirm && !$confirmed) {
            $self->info('Aborting.');
            return;
        }
    }

    if ($self->subject_text eq 'all') {
        $self->index_all;
    }
    elsif ($self->subject_text eq 'queued') {
        $self->index_queued;
    }
    elsif ($self->subject_text eq 'daemon') {
        $self->daemon;
    }
    elsif ($self->subject_text eq 'list') {
        $self->list;
    }
    else {
        die "Not able to modify specific items at this time";
    }

    return 1;
}

sub prompt_for_confirmation {
    my $self = shift;

    my $solr_server = $ENV{GENOME_SYS_SERVICES_SOLR};
    print "Are you sure you want to rebuild the index for the search server at $solr_server? ";
    my $response = <STDIN>;
    chomp $response;
    $response = lc($response);

    return ($response =~ /^(y|yes)$/);
}

sub index_all {
    my $self = shift;

    my $action = $self->action;

    my @classes_to_index = $self->indexable_classes;
    for my $class (@classes_to_index) {
        $self->info("Scanning $class...");
        my @subjects = $class->get();
        for my $subject (@subjects) {
            my $subject_class = $subject->class;
            my $subject_id = $subject->id;
            $self->modify_index($action, $subject_class, $subject_id);
        }
    }

    return 1;
}

my $signaled_to_quit;
sub daemon {
    my $self = shift;

    local $SIG{INT} = sub { print STDERR "\nDaemon will exit as soon as possible.\n"; $signaled_to_quit = 1 };
    local $SIG{TERM} = sub { print STDERR "\nDaemon will exit as soon as possible.\n"; $signaled_to_quit = 1 };

    while (!$signaled_to_quit) {
        my $initial_serial_id = $UR::Context::GET_COUNTER;

        $self->info("Processing index queue...");
        $self->index_queued(max_changes_count => $self->max_changes_per_commit);

        $self->info("Commiting...");
        UR::Context->commit;
        last if $signaled_to_quit;

        $self->info("Pruning...");
        $self->prune_objects_loaded_since($initial_serial_id);
        last if $signaled_to_quit;

        my $loop_sleep = $self->loop_sleep;
        $self->info("Sleeping for $loop_sleep seconds...");
        sleep $loop_sleep;

        last if $signaled_to_quit;

        $self->info("Reloading Genome::Search::IndexQueue...");
        UR::Context->reload('Genome::Search::IndexQueue');
    }

    $self->info("Exiting...");
    return 1;
}

sub prune_objects_loaded_since {
    my ($self, $since) = @_;
    die unless defined $since;

    # Need to unload objects loaded in each loop to prevent memory leak.

    # This whole thing is debatable, i.e. "explicit cleanup" vs "automatic cleanup".
    # View have to be manually cleaned up so I put that in Genome::Search. Objects without
    # data sources do not get unloaded via automatic cleanup which means UR::Values do not.
    # Until that is working automatic cleanup is not an option. Even once it is though it
    # seems like it would be better to just manually cleanup in the interest of efficiency.

    my @all_objects_loaded = (
        UR::Context->current->all_objects_loaded('UR::Object'),
    );
    $self->info("\tBefore pruning all_objects_loaded has " . scalar(@all_objects_loaded));

    # Need to delete views so we can unload UR::Values that are referenced by them
    return if $signaled_to_quit;
    my @views_to_delete =
        grep { $_->isa('UR::Object::View') }
        grep { $_->{'__get_serial'} > $since }
        @all_objects_loaded;
    for (@views_to_delete) {
        last if $signaled_to_quit;
        next if (ref($_) eq 'UR::DeletedRef');
        my $display_name = "(Class: " . $_->class . ", ID: " . $_->id. ")";
        unless ($self->delete_view_and_aspects($_)) {
            $self->debug("Failed to delete object $display_name.");
        } else {
            $self->debug("Deleted object $display_name.");
        }
    }

    # This could be replaced with automatic cleanup by enabling cache pruning.
    return if $signaled_to_quit;
    my @objects_to_unload =
        grep { !$_->isa('UR::DataSource::RDBMS::Entity') }
        grep { $_->__meta__->data_source }
        grep { $_->{'__get_serial'} > $since }
        @all_objects_loaded;
    for (@objects_to_unload) {
        last if $signaled_to_quit;
        my $display_name = "(Class: " . $_->class . ", ID: " . $_->id. ")";
        unless ($_->unload()) {
            $self->debug("Failed to unload object $display_name.");
        } else {
            $self->debug("Unloaded object $display_name.");
        }
    }

    @all_objects_loaded = (
        UR::Context->current->all_objects_loaded('UR::Object'),
    );
    $self->info("\tAfter pruning all_objects_loaded has " . scalar(@all_objects_loaded));
    $self->debug_loaded_objects(@all_objects_loaded);

    return 1;
}

sub debug_loaded_objects {
    my $self = shift;
    my @loaded_objects = @_;
    my %loaded_classes;
    for (@loaded_objects) {
        $loaded_classes{$_->class}++;
    }
    my @keys = sort { $loaded_classes{$a} <=> $loaded_classes{$b} } keys %loaded_classes;
    if (@keys > 10) { @keys = @keys[-10..-1] }
    for (@keys) {
        $self->debug("$_ has " . $loaded_classes{$_});
    }
}

sub list {
    my $self = shift;

    my $index_queue_iterator = Genome::Search::IndexQueue->queue_iterator();

    print join("\t", 'PRIORITY', 'TIMESTAMP', 'SUBJECT_CLASS', 'SUBJECT_ID') . "\n";
    print join("\t", '--------', '---------', '-------------', '----------') . "\n";
    while (my $index_queue_item = $index_queue_iterator->next) {
        print join("\t",
            $index_queue_item->priority,
            $index_queue_item->timestamp,
            $index_queue_item->subject_class,
            $index_queue_item->subject_id,
        ) . "\n";
    }

    return 1;
}

sub index_queued {
    my $self = shift;
    my %params = @_;

    my $max_changes_count = delete $params{max_changes_count};

    # TODO Should optimize this by grouping by subject id and class and removing all related rows
    my $index_queue_iterator = Genome::Search::IndexQueue->queue_iterator();

    my $modified_count = 0;
    while (
        !$signaled_to_quit
        && (!defined($max_changes_count) || $modified_count <= $max_changes_count)
        && (my $index_queue_item = $index_queue_iterator->next)
    ) {
        my $subject_class = $index_queue_item->subject_class;
        my $subject_id = $index_queue_item->subject_id;
        my $action = ($subject_class->get($subject_id) ? 'add' : 'delete');
        if ($self->modify_index($action, $subject_class, $subject_id)) {
            $index_queue_item->delete();
            $modified_count++;
        }
    }

    return 1;
}

sub modify_index {
    my ($self, $action, $subject_class, $subject_id) = @_;

    my $display_name = "(Class: $subject_class, ID: $subject_id)";

    my ($rv, $error);
    if ($action eq 'add') {
        $rv = eval {
            my $subject = $subject_class->get($subject_id);
            unless ($subject) { die "Could not get object $display_name" };
            Genome::Search->add($subject);
        };
        $error = $@;
    }
    elsif ($action eq 'delete') {
        $rv = eval { Genome::Search->delete_by_class_and_id($subject_class, $subject_id) };
        $error = $@;
    }

    if ($error) {
        $self->error($error);
    }

    if ($rv) {
        my $display_action = ($action eq 'add' ? 'Added' : 'Deleted');
        $self->info("$display_action $display_name");
    }
    else {
        my $display_action = ($action eq 'add' ? 'Failed to add' : 'Failed to delete');
        $self->info("$display_action $display_name\n$@");
    }

    return $rv;
}

sub indexable_classes {
    my $self = shift;

    my @searchable_classes = Genome::Search->searchable_classes();

    my @classes_to_add;
    for my $class (@searchable_classes) {
        eval "use $class";
        my $use_errors = $@;
        if ($use_errors) {
            $self->debug("Class ($class) in searchable_classes is not usable ($use_errors).");
            next;
        }

        my $class_is_indexable = Genome::Search->is_indexable($class);
        if (!$class_is_indexable) {
            $self->debug("Class ($class) in searchable_classes is not indexable.");
            next;
        }

        push @classes_to_add, $class;
    }

    return @classes_to_add;
}

sub delete_view_and_aspects {
    my ($self, $view) = @_;
    for my $aspect ($view->aspects) {
        if (my $delegate_view = $aspect->delegate_view) {
            $self->delete_view_and_aspects($delegate_view);
        }
        $aspect->delete;
    }
    $view->delete;
}

1;
