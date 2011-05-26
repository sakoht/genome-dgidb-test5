#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';
use Test::More;

use_ok( 'Genome::Model::Tools::ViromeScreening' ) or die;

my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-ViromeScreening/Titanium17';
ok( -d $data_dir, "Testsuite data dir exists" ) or die;

ok( -s '/gsc/var/cache/testsuite/data/Genome-Model-Tools-ViromeScreening/virome-screening2.xml', "Work xml file exsits" ) or die;

my $temp_dir = Genome::Sys->create_temp_directory();

#create
my $vs = Genome::Model::Tools::ViromeScreening->create(
    fasta_file      => $data_dir.'/Titanium17_2009_05_05_set0.fna',
    barcode_file    => $data_dir.'/454_Sequencing_log_Titanium_test.txt',
    dir             => $data_dir,
    logfile         => $temp_dir.'/log.txt',
    );

ok( $vs, "Created virome screening" );

done_testing();

exit;
