#!/usr/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

no warnings 'redefine';
*Genome::Sys::current_user_is_admin = sub { return 1 };
use warnings;

use_ok('Genome::Sys::User') or die;
use_ok('Genome::Sys::User::Role') or die;
use_ok('Genome::Sys::User::RoleMember') or die;

# Create test role
my $role_name = 'testing1234';
my $role = Genome::Sys::User::Role->create(
    name => $role_name,
);
ok($role, 'created test role');

# Create test user
my $user = Genome::Sys::User->create(
    email => 'testing1234@example.com',
    name => 'testing1234',
);
ok($user, 'created test user');

# Add user to role
my $rv = $role->add_user($user);
ok($rv, 'successfully added user to role');

my $bridge = Genome::Sys::User::RoleMember->get(
    role => $role,
    user => $user,
);
ok($bridge, 'retrieved bridge object');

# Try to add user to the role again, which should fail
my $duplicate_bridge = eval {
    Genome::Sys::User::RoleMember->create(
        role => $role,
        user => $user,
    )
};
ok(!$duplicate_bridge, 'duplicate bridge object could not be created');

done_testing();


