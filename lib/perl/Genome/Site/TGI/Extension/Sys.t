#!/usr/bin/env perl

use strict;
use warnings;

$Genome::Sys::IS_TESTING=1;

use above 'Genome';

use Data::Dumper;
use File::Path;
use File::Spec;
use File::Temp;
use Test::More;
use POSIX ":sys_wait_h";
use File::Slurp;
use Time::HiRes qw(gettimeofday);
use MIME::Base64;

require_ok('Genome::Sys');

# BZIP
my $input_file = "/gsc/var/cache/testsuite/data/Genome-Utility-Filesystem/pileup.cns";
my $source_file = Genome::Sys->create_temp_file_path();
#my $source_file = "/gsc/var/cache/testsuite/running_testsuites/t1/pup.cns"; 
ok(Genome::Sys->copy_file($input_file, $source_file),"Copied test file to temp."); 

my $bzip_file = Genome::Sys->bzip($source_file);

ok (-s $bzip_file, "Bzip file exists.");

my $bunzip_file = Genome::Sys->bunzip($bzip_file);

ok (-s $bunzip_file, "Bunzip file exists.");
ok (-s $bzip_file, "Bzip file exists.");

# FILES
my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
my $base_test_dir = '/gsc/var/cache/testsuite/data/Genome-Utility-Filesystem';

# Read file
my $existing_file = sprintf('%s/existing_file.txt', $base_test_dir);
my $fh = Genome::Sys->open_file_for_reading($existing_file);
ok($fh, "Opened file ".$existing_file);
isa_ok($fh, 'IO::File');
$fh->close;

# No file
my $worked = eval { Genome::Sys->open_file_for_reading };
ok(! $worked, 'open_file_for_reading with no args fails as expected');
like($@, qr/Can't validate_file_for_reading: No file given/, 'Exception looks right');

# File no exist 
my $new_file = sprintf('%s/new_file.txt', $tmpdir);
$worked = eval { Genome::Sys->open_file_for_reading($new_file) };
ok(!$worked, 'Tried to open a non existing file for reading');
like($@, qr/File \($new_file\) does not exist/, 'exception message is correct');

# No read access
my $no_write_dir = sprintf('%s/no_write_dir', $base_test_dir);
my $no_read_file = sprintf('%s/no_read_file.txt', $no_write_dir);
$worked = eval { Genome::Sys->open_file_for_reading($no_read_file) };
ok(!$worked, 'Try to open a file that can\'t be read from');
like($@, qr/File .* does not exist/, 'exception message is correct');

# File is a dir
$worked = eval { Genome::Sys->open_file_for_reading($base_test_dir) };
ok(!$worked, 'Try to open a file, but it\'s a directory');
like($@, qr/File .* exists but is not a plain file/, 'exception message is correct');

#< APPENDING >#
# new file
$fh = Genome::Sys->open_file_for_appending($new_file);
ok($fh, "Opened file for appending: ".$new_file);
isa_ok($fh, 'IO::File');
$fh->close;

# open existing file
$fh = Genome::Sys->open_file_for_appending($new_file);
ok($fh, "Opened file for appending: ".$new_file);
isa_ok($fh, 'IO::File');
$fh->close;

# No file
$worked = eval { Genome::Sys->open_file_for_appending };
ok(!$worked, 'Tried to open undef file for appending');
like($@, qr/No append file given/, 'exception message is correct');

# No write access
my $no_write_file = sprintf('%s/no_write_file.txt', $no_write_dir);
$worked = eval { Genome::Sys->open_file_for_appending($no_write_file) };
ok(!$worked, 'Try to open a file for appending that can\'t be written to');
like($@, qr/Do not have WRITE access to directory/, 'exception message is correct');

# File is a dir
$worked = eval { Genome::Sys->open_file_for_appending($base_test_dir) };
ok(!$worked, 'Try to open a file for appending, but it\'s a directory');
like($@, qr/is a directory and cannot be opend as a file/, 'exception message is correct');
unlink $new_file;
#< APPENDING >#

# WRITING
$fh = Genome::Sys->open_file_for_writing($new_file);
ok($fh, "Opened file ".$new_file);
isa_ok($fh, 'IO::File');
$fh->close;
unlink $new_file;

# No file
$worked = eval { Genome::Sys->open_file_for_writing };
ok(!$worked, 'Tried to open undef file');
like($@, qr/Can't validate_file_for_writing: No file given/, 'exception message is correct');

# File exists
$worked = eval { Genome::Sys->open_file_for_writing($existing_file) };
ok(!$worked, 'Tried to open an existing file for writing');
like($@, qr/Can't validate_file_for_writing: File \($existing_file\) has non-zero size/, 'exception message is correct');

# No write access
$worked = eval { Genome::Sys->open_file_for_writing($no_write_file) };
ok(!$worked, 'Try to open a file that can\'t be written to');
like($@, qr/Can't validate_file_for_writing_overwrite: Do not have WRITE access to directory/, 'exception message is correct');

# File is a dir
$worked = eval { Genome::Sys->open_file_for_writing($base_test_dir) };
ok(!$worked, 'Try to open a file, but it\'s a directory');
like($@, qr/Can't validate_file_for_writing: File .* has non-zero size, refusing to write to it/, 'exception message is correct');

# OVERWRITING
note('open file for overwriting');
$fh = Genome::Sys->open_file_for_overwriting($new_file);
ok($fh, "Opened file for overwriting ".$new_file);
isa_ok($fh, 'IO::File');
$fh->close;
unlink $new_file;

# No file
$worked = eval { Genome::Sys->open_file_for_overwriting };
ok(!$worked, 'Failed to open an undef file for overwriting');
like($@, qr/for over writing\. No file given\./, 'exception message is correct');

# No write access
$worked = eval { Genome::Sys->open_file_for_overwriting($no_write_file) };
ok(!$worked, 'Failed to open a file w/o write access for over writing');
like($@, qr/for over writing\. Do not have write access to directory/, 'exception message is correct');

# File is a dir
$worked = eval { Genome::Sys->open_file_for_overwriting($base_test_dir) };
ok(!$worked, 'Failed to open a directory for over writing');
like($@, qr/for over writing\. It is a directory./, 'exception message is correct');

#< Copying >#
my $file_to_copy_to = $tmpdir.'/file_to_copy_to';
ok(
    Genome::Sys->copy_file($existing_file, $file_to_copy_to),
    'copy_file',
);

eval { Genome::Sys->copy_file($existing_file, $file_to_copy_to) };
ok( $@, 
    'copy_file fails as expected when destination already exists'
);
unlink $file_to_copy_to;

eval { Genome::Sys->copy_file('does_not_exist', $file_to_copy_to) };
ok( $@, 
    'copy_file fails when there is not file to copy',
);

eval { Genome::Sys->copy_file($existing_file) };
ok( $@, 
    'copy_file failed as expected - no destination given',
);

# DIRS
# Real dir
my $dh = Genome::Sys->open_directory($base_test_dir);
ok($dh, "Opened dir: ".$base_test_dir);
isa_ok($dh, 'IO::Dir');

# No dir
$worked = eval { Genome::Sys->open_directory };
ok (!$worked, 'open_directory with no args fails as expected');
like($@, qr/Can't open_directory : No such file or directory/, 'Exception message is correct');

# Dir no exist 
$worked = eval { Genome::Sys->open_directory('/tmp/no_way_this_exists_for_cryin_out_loud') };
ok(!$worked, 'Tried to open a non existing directory');
like($@, qr(Can't open_directory /tmp/no_way_this_exists_for_cryin_out_loud: No such file or directory), 'Exception message is correct');

# Dir is file
$worked = eval { Genome::Sys->open_directory( sprintf('%s/existing_file.txt', $base_test_dir) ) };
ok(!$worked, 'Try to open a directory, but it\'s a file');
like($@, qr/Can't open_directory .*existing_file.txt: Not a directory/, 'Exception message is correct');

# Read access
ok( # good
    Genome::Sys->validate_directory_for_read_access($base_test_dir),
    'validate_directory_for_read_access',
);
my $no_read_dir = sprintf('%s/no_read_dir', $base_test_dir);
$worked = eval { Genome::Sys->validate_directory_for_read_access($no_read_dir) };
ok(!$worked, 'Failed as expected - can\'t read from dir');
like($@, qr/Directory .* is not readable/, 'Exception message is correct');

#test data directory is now read-only so make a temporary directory we know will have write access for testing
my $tmp_dir = File::Temp::tempdir('Genome-Utility-FileSystem-writetest-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);

# Write access
ok( # good
    Genome::Sys->validate_directory_for_write_access( $tmp_dir ),
    'validate_directory_for_write_access',
);
$worked = eval { Genome::Sys->validate_directory_for_write_access($no_write_dir) };
ok(!$worked, 'Failed as expected - can\'t write to dir');
like($@, qr/Directory .* is not writable/, 'Exception message is correct');

# R+W access
ok( # good
    Genome::Sys->validate_directory_for_read_write_access( $tmp_dir ),
    'validate_directory_for_read_write_access',
);
$worked = eval { Genome::Sys->validate_directory_for_read_write_access($no_read_dir) };
ok(!$worked, 'Failed as expected - can\'t read from dir');
like($@, qr/Directory .* is not readable/, 'Exception message is correct');

$worked = eval { Genome::Sys->validate_directory_for_read_write_access($no_write_dir) };
ok(!$worked, 'Failed as expected - can\'t write to dir');
like($@, qr/Directory .* is not writable/, 'Exception message is correct');

my $new_dir = sprintf('%s/new_dir', $tmpdir);
ok( Genome::Sys->create_directory($new_dir), "Created new dir: $new_dir");

my $fifo = $new_dir .'/test_pipe';
`mkfifo $fifo`;
$worked = eval { Genome::Sys->create_directory($fifo) };
ok(!$worked,'failed to create_directory '. $fifo);
like($@, qr/create_directory for path .* failed/, 'exception message is correct');

# tree removal
my $dir_tree_root = $new_dir;
ok(Genome::Sys->create_directory($dir_tree_root), "Created new dir for tree removal test: $dir_tree_root");
my $dir_tree_node = $dir_tree_root . '/node';
ok(Genome::Sys->create_directory($dir_tree_node), "Created new node dir for tree removal test: $dir_tree_node");
ok(Genome::Sys->remove_directory_tree($dir_tree_root), "removed directory tree at $dir_tree_root successfully");
ok(!-d $dir_tree_root, "root directory $dir_tree_root is indeed gone");

# SYMLINK
my $target = $existing_file;
my $new_link = sprintf('%s/existing_link.txt', $tmpdir);

# Good
ok( Genome::Sys->create_symlink($target, $new_link), 'Created symlink');

# Link Failures
$worked = eval { Genome::Sys->create_symlink($target) };
ok(!$worked, "create_symlink with no 'link' fails as expected");
like($@, qr/Can't create_symlink: no 'link' given/, 'exception message is correct');

$worked = eval { Genome::Sys->create_symlink($target, $new_link) };
ok(!$worked, 'Failed as expected - create_symlink when link already exists');
like($@, qr/Link \($new_link\) for target \($target\) already exists/, 'exception message is correct');
unlink $new_link; # remove to not influence target failures below

# Target Failures
$worked = eval { Genome::Sys->create_symlink(undef, $new_link) };
ok(!$worked, 'Failed as expected - create_symlink w/o target');
like($@, qr/Can't create_symlink: no target given/, 'exception message is correct');

$worked = eval { Genome::Sys->create_symlink($tmpdir.'/target', $new_link) };
ok(!$worked, 'Failed as expected - create_symlink when target does not exist');
like($@, qr/Cannot create link \($new_link\) to target \(.*target\): target does not exist/, 'exception message is correct');

# RESOURCE LOCKING
my $bogus_id = '-55555';
$tmp_dir = File::Temp::tempdir(CLEANUP => 1);
my $sub_dir = $tmp_dir .'/sub/dir/test';
ok(! -e $sub_dir,$sub_dir .' does not exist');
ok(Genome::Sys->create_directory($sub_dir),'create directory');
ok(-d $sub_dir,$sub_dir .' is a directory');

test_locking(successful => 1,
    message => 'lock resource_id '. $bogus_id,
    lock_directory => $tmp_dir,
    resource_id => $bogus_id,);

test_locking(successful => 0,
    wait_on_self => 1,
    message => 'failed lock resource_id '. $bogus_id,
    lock_directory => $tmp_dir,
    resource_id => $bogus_id,
    max_try => 1,
    block_sleep => 3,);

ok(Genome::Sys->unlock_resource(
        lock_directory => $tmp_dir,
        resource_id => $bogus_id,
    ), 'unlock resource_id '. $bogus_id);
my $init_lsf_job_id = $ENV{'LSB_JOBID'};
{
    local $ENV{'LSB_JOBID'};
    $ENV{'LSB_JOBID'} = 1;
    test_locking(successful => 1,
        message => 'lock resource with bogus lsf_job_id',
        lock_directory => $tmp_dir,
        resource_id => $bogus_id,);
    test_locking(
        successful=> 1,
        wait_on_self => 1,
        message => 'lock resource with removing invalid lock with bogus lsf_job_id first',
        lock_directory => $tmp_dir,
        resource_id => $bogus_id,
        max_try => 1,
        block_sleep => 3,);
    ok(Genome::Sys->unlock_resource(
            lock_directory => $tmp_dir,
            resource_id => $bogus_id,
        ), 'unlock resource_id '. $bogus_id);
# TODO: add skip test but if we are on a blade, lets see that the locking works correctly
# Above the test is that old bogus locks can get removed when the lsf_job_id no longer exists
# We should test that while an lsf_job_id does exist (ie. our current job) we still hold the lock
    SKIP: {
        skip 'only test the state of the lsf job if we are running on a blade with a job id',
        3 unless ($init_lsf_job_id);
        $ENV{'LSB_JOBID'} = $init_lsf_job_id;
        ok(Genome::Sys->lock_resource(
                lock_directory => $tmp_dir,
                resource_id => $bogus_id,
            ),'lock resource with real lsf_job_id');
        ok(!Genome::Sys->lock_resource(
                lock_directory => $tmp_dir,
                resource_id => $bogus_id,
                max_try => 1,
                block_sleep => 3,
                wait_on_self => 1,
            ),'failed lock resource with real lsf_job_id blocking');
        ok(Genome::Sys->unlock_resource(
                lock_directory => $tmp_dir,
                resource_id => $bogus_id,
            ), 'unlock resource_id '. $bogus_id);
    };
}

# RACE CONDITION
my $base_dir = File::Temp::tempdir("Genome-Utility-FileSystem-RaceCondition-XXXX", DIR=>"/gsc/var/cache/testsuite/running_testsuites/", CLEANUP=>1);

my $resource = "/tmp/Genome-Utility-Filesystem.test.resource.$$";

if (defined $ENV{'LSB_JOBID'} && $ENV{'LSB_JOBID'} eq "1") {
    delete $ENV{'LSB_JOBID'}; 
}

my @pids;

my $children = 20;

for my $child (1...$children) {
    my $pid;
    if ($pid = fork()) {
        push @pids, $pid;
    } else {
        my $output_offset = $child;
        my $tempdir = $base_dir;
        my $output_file = $tempdir . "/" . $output_offset;

        my $fh = new IO::File(">>$output_file");

        my $lock = Genome::Sys->lock_resource(
            resource_lock => $resource,
            block_sleep   => 1,
            wait_announce_interval => 30,
        );
        unless ($lock) {
            print_event($fh, "LOCK_FAIL", "Failed to get a lock" );
            $fh->close;
            exit(1);
        }

        #sleep for half a second before printing this, to let a prior process catch up with
        #printing its "unlocked" message.  sometimes we get a lock (properly) in between the time
        #someone else has given up the lock, but before it had a chance to report that it did.
        select(undef, undef, undef, 0.50);
        print_event($fh, "LOCK_SUCCESS", "Successfully got a lock" );
        sleep 2;

        unless (Genome::Sys->unlock_resource(resource_lock => $resource)) {
            print_event($fh, "UNLOCK_FAIL", "Failed to release a lock" );
            $fh->close;
            exit(1);
        }
        print_event($fh, "UNLOCK_SUCCESS", "Successfully released my lock" );

        $fh->close;
        exit(0);
    }
}

for my $pid (@pids) {
    my $status = waitpid $pid, 0;
}

my @event_log;

for my $child (1...$children) {
    my $report_log = "$base_dir/$child";
    ok (-e $report_log, "Expected to see a report for $report_log");
    if (!-e $report_log) {
        die "Expected output file did not exist";
    } else {
        my @lines = read_file($report_log);
        for (@lines) {
            my ($time, $event, $pid, $msg) = split /\t/;
            my $report = {etime => $time, event=>$event, pid=>$pid, msg=>$msg};
            push @event_log, $report;
        } 
    }
}

ok(scalar @event_log  == 2*$children, "read in got 2 lock/unlock events for each child.");

@event_log = sort {$a->{etime} <=> $b->{etime}} @event_log;
my $last_event;
for (@event_log) {
    if (defined $last_event) {
        my $valid_next_event = ($last_event eq "UNLOCK_SUCCESS" ? "LOCK_SUCCESS" : "UNLOCK_SUCCESS");
        ok($_->{event} eq $valid_next_event, sprintf("Last lock event was a %s so we expected a to see %s, got a %s", $last_event, $valid_next_event, $_->{event}));
    }
    $last_event = $_->{event};
    printf("%s\t%s\t%s\n", $_->{etime}, $_->{pid}, $_->{event});
}

# LOCKING
# DIRECTORY SIZE RECURSIVE
my $dir = File::Temp->tempdir("Genome-Utility-Filesystem-t-directory-size-recursive-XXXX", CLEANUP=>1);
mkdir($dir."/testing",0777);
mkdir($dir."/testing2",0777);
open (F, ">$dir/testing/file1");
print F "1234567890\n";
close F;
open (F, ">$dir/testing2/file2");
print F "1234567890\n";
close F;
my $size = Genome::Sys->directory_size_recursive($dir);
my $expected_size = 22;

is($size,$expected_size,"directory_size_recursive returned the correct size for the test case");

# MD5SUM
my $string = 'hello world';
my $expected_output = '5eb63bbbe01eeed093cb22bb8f5acdc3';
my $output = Genome::Sys->md5sum_data($string);
is($output, $expected_output, 'md5sum_data matches expected output');

eval { Genome::Sys->md5sum_data() };
ok($@, 'md5sum_data with no data throws exception');

# ARCHIVE
my $encoded = <<'END';
H4sIADXeYE4CA+3QXW6EIBAHcJ57ijmAaURd9xQ9xCizQoqwAVy7ty+avvaxTdr8fy8kw3yBjdMk
Wf2othrHoZ69Hrqunl0/dPqMHwY9Kq3HvtWXaztcVKt1f70qatUv2HLhRKTyzt7zLN/lLXlW/9Ab
B3KZjMvFhWVz2YppKMRCMfgnTU+y9ToJ5xgamrZyhMoRy0e+r39355xdDHRLcaVYrCTi4Fb2uaHd
utkeA5h8/WmKt1ostLpQpxTLZzumu6QsD0kcZjlyjHi32EIunOlzDHW7TUxtbGrQyI2LW3jyQouE
WleOBWrhe4i7F7NIQ/Ixi5h8Nsg2pkIPsbLK1wgOT5o5BfZ09/V5W5LXFwUAAAAAAAAAAAAAAAAA
AAAAAPBnfAKKRRlNACgAAA==
END
my $decoded = decode_base64($encoded);
my $tmpdir2 = Genome::Sys->create_temp_directory;
my $tarpath = '/gsc/var/cache/testsuite/data/Genome-Utility-Filesystem/hobbes.tgz';
my $archive = Genome::Sys->extract_archive(from => $tarpath,
    to => $tmpdir2);
ok($archive, 'Extracted gzipped tarball.');
ok($archive->files->[0] eq 'hobbes', "Extracted correct files.");
my $expected = 'Man is distinguished, not only by his reason, but by this '
. 'singular passion from other animals, which is a lust of the mind, that '
. 'by a perseverance of delight in the continued and indefatigable '
. 'generation of knowledge, exceeds the short vehemence of any carnal '
. "pleasure.\n";
my $file = Genome::Sys->open_file_for_reading(File::Spec->catfile(
        $tmpdir2, 'hobbes'));
#cause file reads to read the entire file
{
    local $/;
    my $content = <$file>;
    print $expected;
    ok($content eq $expected, 'File contained expected contents.');
}
# MEM LIMIT
my $mem_limit_kb = Genome::Sys->get_mem_total_from_proc;
ok(defined $mem_limit_kb, 'mem_limit_kb from proc is defined');
$mem_limit_kb = Genome::Sys->get_mem_limit_from_bjobs;
if ($ENV{LSB_JOBID}) {
    ok(defined $mem_limit_kb, 'mem_limit_kb from bjobs (' . $ENV{LSB_JOBID} . ') is defined');
}
else {
    ok(! defined $mem_limit_kb, 'mem_limit_kb from bjobs is not defined');
}

{ # case 1: can't read either
    no warnings 'redefine';
    local $ENV{LSB_JOBID} = 1;
    *Genome::Sys::get_mem_total_from_proc = sub { '' };
    *Genome::Sys::get_mem_limit_from_bjobs = sub { '' };
    my $mem_limit_kb = Genome::Sys->mem_limit_kb;
    is($mem_limit_kb, undef, 'mem_limit_kb is undef');
}
{ # case 2: not limited by LSF
    no warnings 'redefine';
    local $ENV{LSB_JOBID} = 1;
    *Genome::Sys::get_mem_total_from_proc = sub { '4194304' };
    *Genome::Sys::get_mem_limit_from_bjobs = sub { '' };
    my $mem_limit_kb = Genome::Sys->mem_limit_kb;
    is($mem_limit_kb, 4194304, 'mem_limit_kb is 4194304');
}
{ # case 3: limited by LSF
    no warnings 'redefine';
    local $ENV{LSB_JOBID} = 1;
    *Genome::Sys::get_mem_total_from_proc = sub { '4194304' };
    *Genome::Sys::get_mem_limit_from_bjobs = sub { '2097152' };
    my $mem_limit_kb = Genome::Sys->mem_limit_kb;
    is($mem_limit_kb, 2097152, 'mem_limit_kb is 2097152');
}
{ # case 4: limited by LSF but fail to read proc
    no warnings 'redefine';
    local $ENV{LSB_JOBID} = 1;
    *Genome::Sys::get_mem_total_from_proc = sub { '' };
    *Genome::Sys::get_mem_limit_from_bjobs = sub { '2097152' };
    my $mem_limit_kb = Genome::Sys->mem_limit_kb;
    is($mem_limit_kb, 2097152, 'mem_limit_kb is 2097152');
}

done_testing();
exit;

sub test_locking {
    my %params = @_;
    my $successful = delete $params{successful};
    die unless defined($successful);
    my $message = delete $params{message};
    die unless defined($message);

    my $lock = Genome::Sys->lock_resource(%params);
    if ($successful) {
        ok($lock,$message);
        if ($lock) { return $lock; }
    } else {
        ok(!$lock,$message);
    }
    return;
}

sub print_event {
    my $fh = shift;
    my $info = shift;
    my $msg  = shift;

    my ( $seconds, $ms ) = gettimeofday();
    $ms = sprintf("%06d",$ms);
    my $time = "$seconds.$ms";

    my $tp = sprintf( "%s\t%s\t%s\t%s", $time, $info, $$, $msg );

    print $fh $tp, "\n";
    print $tp, "\n";
}

