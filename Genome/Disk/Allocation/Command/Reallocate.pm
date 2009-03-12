package Genome::Disk::Allocation::Command::Reallocate;

use strict;
use warnings;

use Genome;

class Genome::Disk::Allocation::Command::Reallocate {
    is => 'Genome::Disk::Allocation::Command',
    has => [
            allocator_id => {
                             is => 'Number',
                             doc => 'The id for the allocator event',
                         },
        ],
    has_optional => [
                     kilobytes_requested => {
                                             is => 'Number',
                                             doc => 'The disk space allocated in kilobytes',
                                         },
                     reallocator_id => {
                                        is => 'Number',
                                        doc => 'The id for the reallocator pse',
                                  },
                     reallocator => {
                                     calculate_from => 'reallocator_id',
                                     calculate => q|
                                         return GSC::PSE::ReallocateDiskSpace->get($reallocator_id);
                                     |,
                                 },
    ],
    doc => 'A reallocate command to update the allocated disk space',
};


sub create {
    my $class = shift;

    App->init unless App::Init->initialized;

    my $self = $class->SUPER::create(@_);
    unless ($self) {
        return;
    }
    unless ($self->allocator_id) {
        $self->error_message('Allocator id required!  See --help.');
        $self->delete;
        return;
    }
    unless ($self->allocator) {
        $self->error_message('GSC::PSE::AllocateDiskSpace not found for id '. $self->allocator_id);
        $self->delete;
        return;
    }
    unless ($self->reallocator_id) {
        my $reallocate_pse = $self->allocator->reallocate($self->kilobytes_requested);
        unless ($reallocate_pse) {
            $self->error_message('Failed to reallocate disk space');
            $self->delete;
            return;
        }
        $self->reallocator_id($reallocate_pse->pse_id);
    }
    unless ($self->reallocator) {
        $self->error_message('Reallocator not found for reallocator id: '. $self->reallocator_id);
        $self->delete;
        return;
    }
    return $self;
}

sub execute {
    my $self = shift;
    my $reallocator = $self->reallocator;
    $self->status_message('Reallocate PSE id: '. $reallocator->pse_id);
    unless ($self->wait_for_pse_to_confirm(pse => $reallocator)) {
        $self->error_message('Failed to confirm reallocate pse: '. $reallocator->pse_id);
        return;
    }
    return 1;
}

1;
