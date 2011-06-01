#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above "Genome";

use Test::More tests => 13;

use_ok('Genome::Site::WUGC::Sample::Command::Attribute::Add');

my $test_sample = Genome::Site::WUGC::Sample->create(
    name => 'GS_attribute_test.1',
    common_name => 'GSAt' . $_, 
);
isa_ok($test_sample, 'Genome::Site::WUGC::Sample', 'created test sample');

my %attribute_params = (
    name => 'test_attribute_name',
    value => 'test_attribute_value',
    nomenclature => 'WUGC_test',
    sample => $test_sample,
);

my $add_command_1 = Genome::Site::WUGC::Sample::Command::Attribute::Add->create(%attribute_params);
ok($add_command_1, 'created add command');

my $ok_1 = $add_command_1->execute();
ok($ok_1, 'executed add command');
my @attributes = $test_sample->attributes;

is(scalar(@attributes), 1, 'created an attribute');
for my $key (keys %attribute_params) {
    is($attributes[0]->$key, $attribute_params{$key}, 'created attribute has correct ' . $key);
}

#Duplicate add with same param is fine.
my $add_command_2 = Genome::Site::WUGC::Sample::Command::Attribute::Add->create(%attribute_params);
ok($add_command_2, 'created second add command');

my $ok_2 = $add_command_2->execute();
ok($ok_2, 'successfully execute a duplicate request with same value');


#Duplicate add with different param should fail.
$attribute_params{value} = 'test_attribute_value_3';
my $add_command_3 = Genome::Site::WUGC::Sample::Command::Attribute::Add->create(%attribute_params);
ok($add_command_3, 'created second add command');

my $ok_3 = $add_command_3->execute();
ok(!$ok_3, 'did not successfully execute a duplicate request with different value');
