#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';
use Test::More;

use_ok('Genome::Model::Tools::ViromeEvent::BlastX_NT::OuterCheckOutput') or die;

my $data_dir = '/gscmnt/sata420/info/testsuite_data/Genome-Model-Tools-ViromeScreening/Titanium17/Titanium17_undecodable';
ok( -d $data_dir, "Test suite dir exists" ) or die;

my $temp_dir = Genome::Utility::FileSystem->create_temp_directory(); #just need some place for log file

my $c = Genome::Model::Tools::ViromeEvent::BlastX_NT::OuterCheckOutput->create(
    dir     => $data_dir,
    logfile => $temp_dir.'/log.txt',
    );
ok($c, "Created blastx-nt outer check event") or die;

ok($c->execute, "Successfully executed event") or die;

my $files_for_blast = $c->files_for_blast;
my $expected_file = '/gscmnt/sata420/info/testsuite_data/Genome-Model-Tools-ViromeScreening/Titanium17/Titanium17_undecodable/Titanium17_undecodable.BNFiltered_TBLASTX_nt/Titanium17_undecodable.BNFiltered.fa_file0.fa';

is_deeply( $files_for_blast, [ $expected_file, ], "Got expected file for blast" );

done_testing();

exit;
