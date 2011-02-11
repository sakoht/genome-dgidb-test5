#! /gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

use Test::More;

use_ok('Genome::Model::Command::Report::SummaryOfBuilds') or die;

my $rows = [
    [qw| 2816929868 98421143 Succeeded 2009-08-13 |],
    [qw| 2816929868 98421142 Succeeded 2009-08-27 |],
    [qw| 2816929867 98421141 Succeeded 2009-12-29 |],
    [qw| 2816929867 98421140 Succeeded 2009-08-28 |],
    [qw| 2816929867 98421139 Succeeded 2009-08-27 |],
    ];
no warnings 'redefine'; # commant out to see real data
*Genome::Model::Command::Report::SummaryOfBuilds::_selectall_arrayref = sub{ return $rows; };
use warnings;

my $sob = Genome::Model::Command::Report::SummaryOfBuilds->create(
    work_order_id => 2196657, 
    #email => $ENV{USER}.'@genome.wustl.edu',
    #all_datasets => 1,
);
ok($sob, 'create');
$sob->dump_status_messages(1);
ok($sob->execute, 'execute');
is($sob->were_builds_found, 5, 'Got all 5 builds for 2 models');

$sob = Genome::Model::Command::Report::SummaryOfBuilds->create(
    work_order_id => 2196657, 
    most_recent_build_only => 1,
);
ok($sob, 'create');
$sob->dump_status_messages(1);
ok($sob->execute, 'execute');
is($sob->were_builds_found, 2, 'Got only latest builds for 2 models.'); 

$sob = Genome::Model::Command::Report::SummaryOfBuilds->create(
    processing_profile_id => 2067049, # WashU amplicon assembly
    most_recent_build_only => 1,
);
ok($sob, 'create');
$sob->dump_status_messages(1);
ok($sob->execute, 'execute');

$sob = Genome::Model::Command::Report::SummaryOfBuilds->create(
    type_name => 'amplicon assembly',
);
ok($sob, 'create');
$sob->dump_status_messages(1);
ok($sob->execute, 'execute');

$sob = Genome::Model::Command::Report::SummaryOfBuilds->create(
    subject_names => 'HMPZ-764083206-700024109,HMPZ-764083206-700037552',
);
ok($sob, 'create');
$sob->dump_status_messages(1);
ok($sob->execute, 'execute');

$sob = Genome::Model::Command::Report::SummaryOfBuilds->create(
    subject_names => 'HMPZ-764083206-700024109,HMPZ-764083206-700037552',
);
ok($sob, 'create');
$sob->dump_status_messages(1);
ok($sob->execute, 'execute');

$sob = Genome::Model::Command::Report::SummaryOfBuilds->create(
    work_order_id => undef, 
);
ok($sob, 'create');
$sob->dump_status_messages(1);
ok(!$sob->execute, 'execute');

$sob = Genome::Model::Command::Report::SummaryOfBuilds->create(
    days => 'pp',
);
ok($sob, 'create');
$sob->dump_status_messages(1);
ok(!$sob->execute, 'execute');

done_testing();
exit;

