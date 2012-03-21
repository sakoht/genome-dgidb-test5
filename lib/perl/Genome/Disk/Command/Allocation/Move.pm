package Genome::Disk::Command::Allocation::Move;

use strict;
use warnings;
use Genome;

class Genome::Disk::Command::Allocation::Move {
    is => 'Command::V2',
    has => [
        allocations => {
            is => 'Genome::Disk::Allocation',
            is_many => 1,
            shell_args_position => 1,
            doc => 'Allocations to move',
        }
    ],
    has_optional => [
        target_volume => {
            is => 'Genome::Disk::Volume',
            doc => 'Volume that allocations are to be moved to',
        },
        target_group => {
            is => 'Genome::Disk::Group',
            doc => 'Group that allocations are to be moved to',
        },
    ],
    doc => 'move alloations from one volume to another',
};

sub help_detail {
    return <<EOS
Moves allocations from one volume to another. Can specify a specific volume
to move them to or provide a group from which a volume will be selected
EOS
}

sub help_brief {
    return 'moves alloations from one volume to another';
}

sub execute {
    my $self = shift;
    unless ($self->target_volume or $self->target_group) {
        Carp::confess 'Must provide either a target volume or a target group!';
    }

    for my $allocation ($self->allocations) {
        my %params;
        if ($self->target_volume) {
            $params{target_mount_path} = $self->target_volume->mount_path;
        }
        else {
            $params{disk_group_name} = $self->target_group->disk_group_name;
        }
        $allocation->move(%params);
    }

    $self->status_message("Successfully moved allocations!");
    return 1;
}

1;

