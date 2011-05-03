#!/gsc/bin/perl

use strict;
use warnings;

use above 'Genome';
use Test::More;
use File::Temp 'tempdir';
use File::Slurp;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
$ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;

$| = 1;
use_ok('Genome::Disk::Allocation') or die;
use_ok('Genome::Disk::Assignment') or die;
use_ok('Genome::Disk::Volume') or die;
use_ok('Genome::Disk::Group') or die;

my $test_dir_base = '/gsc/var/cache/testsuite/running_testsuites/';
my $test_dir = tempdir(
    TEMPLATE => 'allocation_testing_XXXXXX',
    DIR => $test_dir_base,
    UNLINK => 1,
    CLEANUP => 1,
);

# Add our testing group to the allowed list of disk groups
push @Genome::Disk::Allocation::APIPE_DISK_GROUPS, 'testing_group';
$Genome::Disk::Allocation::CREATE_DUMMY_VOLUMES_FOR_TESTING = 0;

# Make a dummy group and some dummy volumes
my $group = Genome::Disk::Group->create(
    disk_group_name => 'testing_group',
    permissions => '755',
    sticky => '1',
    subdirectory => 'testing',
    unix_uid => 0,
    unix_gid => 0,
);
ok($group, 'successfully made testing group') or die;

# Make several dummy volumes
my @volumes;
for (1..5) {
    my $volume_path = tempdir(
        TEMPLATE => "test_volume_" . $_ . "_XXXXXXX",
        DIR => $test_dir,
        CLEANUP => 1,
        UNLINK => 1,
    );
    my $volume = Genome::Disk::Volume->create(
        id => $_,
        hostname => 'foo',
        physical_path => 'foo/bar',
        mount_path => $volume_path,
        total_kb => 1024,
        unallocated_kb => 1024,
        disk_status => 'active',
        can_allocate => '1',
    );
    ok($volume, 'made testing volume') or die;
    push @volumes, $volume;

    my $assignment = Genome::Disk::Assignment->create(
        dv_id => $volume->id,
        dg_id => $group->id,
    );
    ok($assignment, 'made disk assignment') or die;
}

# Make sure dummy objects can be committed
ok(UR::Context->commit, 'commit of dummy objects to db successful') or die;

# Create a dummy allocation
# This gets made in temp, but I'm only interested in the dirname
my $allocation_path = tempdir(
    TEMPLATE => "allocation_test_1_XXXXXX",
    CLEANUP => 1,
    UNLINK => 1,
);

my $user = Genome::Sys::User->create(email => 'fakeguy@genome.wustl.edu', name => 'Fake McFakerton');
ok($user, 'created user');

my %params = ( 
    disk_group_name => 'testing_group',
    mount_path => $volumes[0]->mount_path,
    allocation_path => $allocation_path,
    kilobytes_requested => 100,
    owner_class_name => 'Genome::Sys::User',
    owner_id => $user->username,
    group_subdirectory => 'testing',
);
my $allocation = Genome::Disk::Allocation->create(%params);
ok($allocation, 'successfully created test allocation');

# Try to make another allocation that's a subdir of the first, which should fail
$params{allocation_path} .= '/subdir';
my $subdir_allocation = eval { Genome::Disk::Allocation->create(%params) };
ok(!$subdir_allocation, 'allocation creation failed as expected');

# Now try to make an allocation that's too big for the volume
$params{allocation_path} =~ s/allocation_test_1/allocation_test_2/;
$params{allocation_path} =~ s/subdir//;
$params{kilobytes_requested} = 10000;
my $big_allocation = eval { Genome::Disk::Allocation->create(%params) };
ok(!$big_allocation, 'allocation fails when request is too big, as expected');

# Turn off all volumes in the group, make sure allocation fails
map { $_->can_allocate(0) } @volumes;
delete $params{mount_path};
my $fail_allocation = eval { Genome::Disk::Allocation->create(%params) };
ok(!$fail_allocation, 'failed to allocate when volumes are turned off, as expected');

# Turn on one volume, make sure allocation succeeds
$volumes[-1]->can_allocate(1);
$params{kilobytes_requested} = 100;
my $other_allocation = Genome::Disk::Allocation->create(%params);
ok($other_allocation, 'created another allocation without problem');
ok($other_allocation->mount_path eq $volumes[-1]->mount_path, 'allocation landed on only allocatable mount path');

# Try to delete
Genome::Disk::Allocation->delete(allocation_id => $other_allocation->id);
isa_ok($other_allocation, 'UR::DeletedRef', 'successfully removed allocation');

# Lower size of allocation's volume, then reallocate with move and make sure that works
my $touch_file = $allocation->absolute_path . "/test_file";
system("touch $touch_file");
ok(-e $touch_file, "touched file exists in allocation directory");

my $current_volume = $allocation->volume;
my $old_allocation_size = $allocation->kilobytes_requested;
$current_volume->unallocated_kb(100);
my $current_volume_unallocated_kb = $current_volume->unallocated_kb;

my $move_rv = Genome::Disk::Allocation->reallocate(allocation_id => $allocation->id, kilobytes_requested => 500, allow_reallocate_with_move => 1);

ok($allocation->volume->mount_path ne $current_volume, "allocation moved to new volume");
ok(-e $allocation->absolute_path . "/test_file", "touched file correctly moved to new allocation directory");
ok(!Genome::Disk::Allocation->get(mount_path => $current_volume->mount_path, allocation_path => $allocation->allocation_path), 'no redundant allocation on old volume');
ok($current_volume->unallocated_kb == ($current_volume_unallocated_kb + $old_allocation_size), 'volume size indicates allocation has been moved');

# Now delete the allocation
Genome::Disk::Allocation->delete(allocation_id => $allocation->id);
isa_ok($allocation, 'UR::DeletedRef', 'other allocation removed successfully');

# Now do a big race condition test. Make a bunch of child processes, perform operations on some allocations, and
# make sure that nothing gets stuck in a deadlock
print "*** Starting race condition test\n";
if (Genome::DataSource::GMSchema->has_default_handle) { # Prevents craziness when the child processes try to close the dbh
    print("Disconnecting GMSchema default handle.\n");
    Genome::DataSource::GMSchema->disconnect_default_dbh();
}
if (Genome::DataSource::Oltp->has_default_handle) { # Prevents craziness when the child processes try to close the dbh
    print("Disconnecting Oltp default handle.\n");
    Genome::DataSource::Oltp->disconnect_default_dbh();
}
map { $_->can_allocate(1) } @volumes; # Turn on the volumes

my @pids;
my $children = 20;
for my $child (1..$children) {
    my $pid;
    if ($pid = fork()) {
        push @pids, $pid;
    }
    else {
        print "*** Spinning up child process $child, PID $$\n";
        my $volume = $volumes[$child % @volumes];
        do_race_lock($child, $group, $volume, $test_dir);
        print "*** Child $child exiting\n";
        exit 0;
    }
}

for my $pid (@pids) {
    my $status = waitpid $pid, 0;
}

for my $child (1..$children) {
    my $log = "$test_dir/child_$child";
    ok(-e $log, 'found child process log file') or next;

    my @lines = read_file($log);
    ok(@lines == 3, 'there are three lines of output in the log, create/reallocate/deallocate') || system("cat $log");
    for my $line (@lines) {
        chomp $line;
        ok($line =~ /SUCCESS/, "log indicates success: $line");
    }

    unlink $log;
}

done_testing();

# 
# Methods
#
sub do_race_lock {
    my ($child_id, $group, $volume, $test_dir) = @_;
    $UR::Object::Type::autogenerate_id_iter += $child_id;

    my $output_file = $test_dir . "/child_$child_id";
    my $fh = new IO::File(">$output_file");

    my $path = tempdir(
        TEMPLATE => 'allocation_lock_testing_' . $child_id . '_XXXXXXX',
        DIR => $volume->mount_path, 
        CLEANUP => 1,
        UNLINK => 1,
    );

    # The volume/group objects still exist (they were created in the parent process), but they aren't in the 
    # UR cache for the child process, which means that gets/loads will not find them. Overriding the 
    # get/load methods as needed on these classes to just return the objects gets around this.
    local *Genome::Disk::Group::get = sub { return $group };
    local *Genome::Disk::Volume::get = sub { return $volume };
    local *Genome::Disk::Volume::load = sub { return $volume };

    print "*** Child $child_id creating new allocation on volume " . $volume->mount_path . "\n";

    my $allocation = Genome::Disk::Allocation->create(
        mount_path => $volume->mount_path,
        disk_group_name => $group->disk_group_name,
        allocation_path => $path,
        kilobytes_requested => 10,
        owner_class_name => 'Genome::Sys::User',
        owner_id => $user->username,
        group_subdirectory => $group->subdirectory,
    );

    unless ($allocation) {
        $fh->print("ALLOCATION_CREATE_FAIL\n");
        $fh->close;
        return;
    }
    else {
        $fh->print("ALLOCATION_CREATE_SUCCESS\n");
    }

    sleep 1;
    print "*** Child $child_id reallocating\n";

    my $reallo_rv = Genome::Disk::Allocation->reallocate(
        allocation_id => $allocation->id,
        kilobytes_requested => 5,
    );

    unless (defined $reallo_rv and $reallo_rv) {
        $fh->print("REALLOCATION_FAIL\n");
        $fh->close;
        return;
    }
    else {
        $fh->print("REALLOCATION_SUCCESS\n");
    }

    sleep 1;
    print "*** Child $child_id deallocating!\n";

    my $deallo_rv = Genome::Disk::Allocation->delete(
        allocation_id => $allocation->id,
    );

    unless (defined $deallo_rv and $deallo_rv) {
        $fh->print("DEALLOCATION_FAIL\n");
        $fh->close;
        return;
    }
    else {
        $fh->print("DEALLOCATION_SUCCESS\n");
    }

    $fh->close;
    return;
}




