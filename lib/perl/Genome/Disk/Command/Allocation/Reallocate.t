#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

use_ok('Genome::Disk::Command::Allocation::Reallocate') or die;
use_ok('Genome::Disk::Allocation') or die;

my $allocation = Genome::Disk::Allocation->create(
    disk_group_name => 'info_apipe',
    allocation_path => 'command/allocation/deallocate/test',
    kilobytes_requested => 100,
    owner_class_name => 'UR::Value',
    owner_id => 'test',
);
ok($allocation, 'Successfully created test allocation') or die;

my $cmd = Genome::Disk::Command::Allocation::Reallocate->create(
    allocations => [$allocation],
    kilobytes_requested => 200,
);
ok($cmd, 'Successfully created reallocate command object') or die;

my $rv = $cmd->execute;
ok($rv, 'Successfully created command');

is($allocation->kilobytes_requested, 200, 'allocation correctly resized');

done_testing();



