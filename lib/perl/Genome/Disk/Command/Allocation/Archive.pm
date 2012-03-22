package Genome::Disk::Command::Allocation::Archive;

use strict;
use warnings;
use Genome;
use Carp;

class Genome::Disk::Command::Allocation::Archive {
    is => 'Command::V2',
    has => [
        allocations => {
            is => 'Genome::Disk::Allocation',
            is_many => 1,
            shell_args_position => 1,
            doc => 'allocations to be archived',
        },
    ],
    doc => 'archives the given allocations',
};

sub help_detail {
    return 'archives the given allocations, putting them on tape and removing them from filesystem';
}

sub help_brief {
    return 'archives the given allocations';
}

sub _is_hidden_in_docs {
    return !Genome::Sys->current_user_has_role('archive');
}

sub execute {
    my $self = shift;
    $self->status_message("Starting archive command...");

    for my $allocation ($self->allocations) {
        $self->debug_message("Archiving allocation " . $allocation->id);
        my $rv = $allocation->archive;
        unless ($rv) {
            Carp::confess "Could not archive allocation " . $allocation->id;
        }
        $self->debug_message("Finished archiving allocation " . $allocation->id);
    }

    $self->status_message("Done archiving, exiting...");
    return 1;
}

1;

