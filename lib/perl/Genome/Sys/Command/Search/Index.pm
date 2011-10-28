package Genome::Sys::Command::Search::Index;

use Genome;

class Genome::Sys::Command::Search::Index {
    is => ['Genome::Role::Logger', 'Command'],
    has => [
        subject_text => {
            is => 'Text',
            shell_args_position => 1,
        },
        confirm => {
            is => 'Boolean',
            default => 1,
        },
        testing => {
            is => 'Boolean',
            default => 1,
        },
    ],
};

sub execute {
    my $self = shift;

    if ($self->testing) {
        local $ENV{UR_DBI_NO_COMMIT} = 1;
        local $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    }

    my $confirmed = $self->prompt_for_confirmation() if $self->confirm;
    if ($self->confirm && !$confirmed) {
        print "Aborting.\n";
        return;
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
    else {
        my $subject = $self->get_subject_from_subject_text();
        $self->index($subject) if $subject;
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

sub get_subject_from_subject_text {
    my $self = shift;

    my ($subject_class, $subject_id) = $self->subject_text =~ /^(.*)=(.*)$/;
    unless ($subject_class && $subject_id) {
        $self->error_message("Failed to parse subject_text (" . $self->subject_text . ") for class and ID. Must be in the form Class=ID.");
        return;
    }

    unless ($subject_class->isa('UR::Object')) {
        $self->error_message("Class ($subject_class) is not recognized as an UR object.");
        return;
    }

    my $subject = $subject_class->get($subject_id);
    unless ($subject) {
        $self->error_message("Failed to get object (Class: $subject_class, ID: $subject_id).");
        return;
    }

    return $subject;
}

sub index_all {
    my $self = shift;

    my @classes_to_index = $self->indexable_classes;
    for my $class (@classes_to_index) {
        $self->info("Scanning $class...\n");
        my @subjects = $class->get();
        for my $subject (@subjects) {
            $self->index($subject);
        }
    }

    return 1;
}

sub daemon {
    my $self = shift;

    my $loop = 1;
    local $SIG{INT} = sub { $loop = 0 };
    while ($loop) {
        $self->index_queued;
        UR::Context->commit;
        UR::Context->reload('Genome::Search::IndexQueue');
        sleep 2 if $self->testing;
    }

    return 1;
}

sub index_queued {
    my $self = shift;

    my $index_queue_iterator = Genome::Search::IndexQueue->create_iterator(
        '-order_by' => 'timestamp',
    );

    while (my $index_queue_item = $index_queue_iterator->next) {
        my $subject = $index_queue_item->subject;
        if ($self->index($subject)) {
            $index_queue_item->delete() unless $self->testing;
        }
    }

    return 1;
}

sub index {
    my ($self, $subject) = @_;

    my $class = $subject->class;
    my $id = $subject->id;

    my $rv = ($self->testing ? 1 : eval { Genome::Search->add($subject) });
    if ($rv) {
        $self->info("Indexed (Class: $class, ID: $id)\n");
    }
    else {
        $self->error_message("Failed (Class: $class, ID: $id)");
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
            $self->debug("Class ($class) in searchable_classes is not usable ($use_errors).\n");
            next;
        }

        my $class_is_indexable = Genome::Search->is_indexable($class);
        if (!$class_is_indexable) {
            $self->debug("Class ($class) in searchable_classes is not indexable.\n");
            next;
        }

        push @classes_to_add, $class;
    }

    return @classes_to_add;
}
