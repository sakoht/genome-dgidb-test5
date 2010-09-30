#!/usr/bin/env perl
use strict;
use warnings;
use above "Genome";
use Test::MockObject;
use Test::More;

my $i = Test::MockObject->new();
$i->set_isa('Genome::InstrumentData::AlignmentResult', 'UR::Object');
$i->set_always('__display_name__', "Alignment Result 1");
$i->set_always('delete', 1);
ok($i, "created a new imported instrument data");

my $i2 = Test::MockObject->new();
$i2->set_isa('Genome::InstrumentData::AlignmentResult', 'UR::Object');
$i2->set_always('__display_name__', "Alignment Result 2");
$i2->set_always('delete', 1);
ok($i2, "created a new imported instrument data");

my $remove_command = Genome::InstrumentData::Command::AlignmentResult::Remove->create(alignment_results => [$i, $i2]);
ok($remove_command->execute(), "command succeeded");

done_testing();
