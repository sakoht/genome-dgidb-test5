package Genome::Disk::Allocation;

# Adaptor for GSC::DiskAllocation

# Do NOT use this module from anything in the GSC schema,
# though the converse will work just fine.

# This module will handle all PSE calls based on modifications

use strict;
use warnings;

use Genome;
use Genome::Utility::AsyncFileSystem qw/on_each_line/;
use Sys::Hostname qw/hostname/;

class Genome::Disk::Allocation {
    table_name => "(select * from disk_allocation\@dw) disk_allocation",
    id_by => [
              allocator_id => {
                               is => 'Number',
                               doc => 'The id for the allocator event',
                           },
          ],
    has => [
            disk_group_name => {
                                  is => 'Text',
                                  doc => 'The name of the disk group',
                              },
            mount_path => {
                           is => 'Text',
                           doc => 'The mount path of the disk volume',
                       },
            allocation_path => {
                                is => 'Text',
                                doc => 'The sub-dir of the disk volume for which space is allocated',
                            },
            kilobytes_requested => {
                                    is => 'Number',
                                    doc => 'The disk space allocated in kilobytes',
                                },
            kilobytes_used => {
                               is => 'Number',
                               doc => 'The actual disk space used by owner',
                           },
            owner_class_name => {
                                 is => 'Text',
                                 doc => 'The class name for the owner of this allocation',
                             },
            owner_id => {
                         is => 'Number',
                         doc => 'The id for the owner of this allocation',
                         },
            owner => { id_by => 'owner_id', is => 'UR::Object', id_class_by => 'owner_class_name' },
            group_subdirectory => {
                                   is => 'Text',
                                   doc => 'The group specific subdirectory where space is allocated',
            },
            absolute_path => {
                              calculate_from => ['mount_path','group_subdirectory','allocation_path'],
                              calculate => q|
                                  return $mount_path .'/'. $group_subdirectory .'/'. $allocation_path;
                              |,
                          },
        ],
        has_optional => [
                         allocator => {
                                       calculate_from => 'allocator_id',
                                       calculate => q|
                                                     return GSC::PSE::AllocateDiskSpace->get($allocator_id);
                                       |,
                                       doc => 'The allocate disk space PSE',
                                   },
                     ],
        data_source => 'Genome::DataSource::GMSchema',
};

sub allocate {
    my $class = shift;
    my %params = (@_);

    my @required_params = qw (allocation_path disk_group_name kilobytes_requested owner_class_name owner_id);
    for (@required_params) {
        unless (defined($params{$_})) {
            die($_ .' param is required to allocate in '. $class .' and got params '. "\n". Data::Dumper::Dumper(%params) ."\n");
        }
    }
    if ($ENV{UR_DBI_NO_COMMIT}) {
        my $allocate_cmd = Genome::Disk::Allocation::Command::Allocate->execute(%params);
    } else {
        my $allocate_cmd = sprintf('genome disk allocation allocate --allocation-path=%s --disk-group-name=%s --kilobytes-requested=%s --owner-class-name=%s --owner-id=%s',
                                $params{allocation_path},
                                $params{disk_group_name},
                                $params{kilobytes_requested},
                                $params{owner_class_name},
                                $params{owner_id},
                            );
        if ($params{mount_path}) {
            $allocate_cmd .= ' --mount-path='. $params{mount_path};
        }
        unless($class->monitor_allocate_command($allocate_cmd)) {
            die('Failed to allocate disk space with command '. $allocate_cmd);
        }
    }
    my $allocation = Genome::Disk::Allocation->load(
                                                   allocation_path => $params{allocation_path},
                                                   disk_group_name => $params{disk_group_name},
                                                   owner_class_name => $params{owner_class_name},
                                                   owner_id => $params{owner_id},
                                               );
    unless ($allocation) {
        die('Failed to get '. $params{disk_group_name} .' disk allocation for '. $params{owner_class_name} .'('. $params{owner_id}
            .') with allocation path '. $params{allocation_path});
    }
    return $allocation;
}

sub reallocate {
    my $self = shift;
    my %params = @_;
    if ($ENV{UR_DBI_NO_COMMIT}) {
        my $reallocate_cmd = Genome::Disk::Allocation::Command::Reallocate->execute(
                                                                                    allocator_id => $self->allocator_id,
                                                                                    %params
                                                                                );
        unless ($reallocate_cmd) {
            $self->error_message('Failed to reallocate disk space with command '. $reallocate_cmd);
            return;
        }
    } else {
        my $reallocate_cmd = sprintf('genome disk allocation reallocate --allocator-id=%s',$self->allocator_id);
        if ($params{kilobytes_requested}) {
            $reallocate_cmd .= ' --kilobytes-requested='. $params{kilobytes_requested};
        }
        unless($self->monitor_allocate_command($reallocate_cmd)) {
            $self->error_message('Failed to reallocate disk space with command '. $reallocate_cmd);
            return;
        }
    }
    return 1;
}

sub deallocate {
    my $self = shift;
    if ($ENV{UR_DBI_NO_COMMIT}) {
        my $deallocate_cmd = Genome::Disk::Allocation::Command::Deallocate->execute(allocator_id => $self->allocator_id);
        unless ($deallocate_cmd) {
            $self->error_message('Failed to deallocate disk space with command '. $deallocate_cmd);
            return;
        }
    } else {
        my $deallocate_cmd = sprintf('genome disk allocation deallocate --allocator-id=%s',$self->allocator_id);
        unless ($self->monitor_allocate_command($deallocate_cmd)) {
            $self->error_message('Failed to deallocate disk space with command '. $deallocate_cmd);
            return;
        }
    }
    return 1;
}

sub get_actual_disk_usage {
    my $self = shift;
    
    my $allocator = $self->allocator;

    my $kb = $allocator->get_actual_disk_usage;

    return $kb;
}

sub pse_not_complete {
    my $self = shift;
    my $pse = shift;
    my @not_completed = grep { $_ eq $pse->pse_status } ('scheduled', 'wait', 'confirm', 'confirming');
    unless (@not_completed) {
        return;
    }
    return 1;
}

## warning times in seconds
our $after_start = 600;
our $after_lock_acquired = 120;
sub monitor_allocate_command {
    my $self = shift;
    my $cmd = shift;

    my $pid;
    my $lock_acquire_time;         # will be set once we see the lock acquired
    my $ow;                        # overall watcher;
    my $w;                         # after lock acquired watcher;
    
    $ow = AnyEvent->timer(
        after => $after_start,
        cb => sub {
           $self->send_message_about_command($cmd,$pid,$after_start,0);
           undef $ow;
           undef $w;
    });
    
    $self->status_message('Allocation process started at ' . UR::Time->now);
    local $ENV{'MONITOR_ALLOCATE_LOCK'} = 1;
    my $cv = Genome::Utility::AsyncFileSystem->shellcmd(
        cmd => $cmd,
        '2>' => on_each_line {
            if (defined $_[0]) {
                if ($_[0] !~ /^genome allocate: STATUS:/) {
                    print $_[0];
                }
                if ($_[0] =~ /^genome allocate: STATUS: Lock acquired/) {
                    $self->status_message('Allocation lock acquired at ' . UR::Time->now);
                    $w = AnyEvent->timer(
                        after => $after_lock_acquired,
                        cb => sub {
                           $self->send_message_about_command($cmd,$pid,$after_lock_acquired,1);
                           undef $ow;
                           undef $w;
                    });
                }
            }
        },
        '$$' => \$pid
    );
    $cv->cb(sub {
        undef $ow;
        undef $w;
        $self->status_message('Allocation command ended at ' . UR::Time->now);
    });
    
    return $cv->recv;
}

sub send_message_about_command {
    my $self = shift;
    my $cmd = shift;
    my $pid = shift;
    my $after = shift;
    my $was_lock_acquired = shift;

    my $lock_msg = $was_lock_acquired 
        ? 'Lock Held' 
        : '';

    my $message = <<MESSAGE;
To whom it may concern,

This command:

$cmd

Has not exited after $after seconds. $lock_msg

Host: %s
My Pid: %s 
Allocation Pid: %s
LSF Job: %s
User: %s

This is the only warning you will receive about this process.  Action
may be required.
MESSAGE

    my $from = '"' . __PACKAGE__ . sprintf('" <%s@genome.wustl.edu>', $ENV{USER});

    my $to = join(', ', map { Genome::Config->user_email($_) } Genome::Config->admin_notice_users());
    my $subject = 'Allocation problem on ' . hostname . ' pid ' . $pid . '. ' . $lock_msg;
    my $data = sprintf($message,
        hostname,$$,$pid,($ENV{LSB_JOBID} || ''),scalar(getpwuid($<)));

    my $msg = MIME::Lite->new(
        From => $from,
        To => $to,
        Subject => $subject,
        Data => $data
    );
    $msg->send();

}


1;




