#!/usr/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

use_ok('Genome::Sys') or die;

# Set up test data

my $test_base_dir = '/gsc/var/cache/testsuite/running_testsuites';
$ENV{TMPDIR} = $test_base_dir;

my $test_dir = Genome::Sys->create_temp_directory;
ok(-d $test_dir, "created test directory at $test_dir");

my $other_test_dir = Genome::Sys->create_temp_directory;
ok(-d $other_test_dir, "created another test directory at $other_test_dir");

my @files = qw/ a.out b.out c.out d.blah e.blah /;
for my $file (@files) {
    my $path = join('/', $test_dir, $file);
    system("touch $path");
    ok(-e $path, "created test file at $path");
}
system("mkdir $test_dir/test");

my $rv = Genome::Sys->rsync_directory(
    source_directory => $test_dir,
    target_directory => $other_test_dir,
    file_pattern => "*.out",
);
ok($rv, 'successfully copied directory');
for my $file (grep { $_ =~ /\.out$/ } @files) {
    my $path = join('/', $other_test_dir, $file);
    ok(-e $path, "found copy of file at $path");
}

# Now copy without a pattern
my $yet_another_test_dir = Genome::Sys->create_temp_directory;
ok(-d $yet_another_test_dir, "created another test directory at $yet_another_test_dir");

$rv = Genome::Sys->rsync_directory(
    source_directory => $test_dir,
    target_directory => $yet_another_test_dir,
);
ok($rv, 'successfully copied directory');
for my $file (@files) {
    my $path = join('/', $yet_another_test_dir, $file);
    ok(-e $path, "found copy of file at $path");
}
ok(-d ($yet_another_test_dir . "/test"), "found copy of test directory");

done_testing();
