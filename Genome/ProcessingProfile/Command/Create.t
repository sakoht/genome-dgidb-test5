#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";

use Data::Dumper 'Dumper';
use Genome::ProcessingProfile::Test;
use Test::More 'no_plan';

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

use_ok('Genome::ProcessingProfile::Command::Create') or die;

ok(
    Genome::ProcessingProfile::Command::Create->sub_command_classes,
    'Sub command classes',
);

# Create a in memory create command for tester
class Genome::ProcessingProfile::Command::Create::Tester {
    is => 'Genome::ProcessingProfile::Command::Create',
    has => [ sequencing_platform => {}, dna_source => {}, ],
};
my %params = Genome::ProcessingProfile::Test->params_for_test_class;
delete $params{type_name};
my $creator = Genome::ProcessingProfile::Command::Create::Tester->create(%params);
ok($creator, "Created processing profile create command");
ok($creator->execute, "Executed");

exit;

#$HeadURL$
#$Id$
