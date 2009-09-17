#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';
use Test::More tests => 6;

use Genome::Utility::FileSystem;

my $tmp = Genome::Utility::FileSystem->create_temp_directory();
if (-e $tmp .'/Quality/report.xml') {
    unlink $tmp .'/Quality/report.xml';
}
my $gerald_directory = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Align-Maq/test_sample_name';
my $instrument_data = Genome::InstrumentData::Solexa->create_mock(
                                                                  id => '-123456',
                                                                  sequencing_platform => 'solexa',
                                                                  sample_name => 'test_sample_name',
                                                                  library_name => 'test_library_name',
                                                                  run_name => 'test_run_name',
                                                                  subset_name => 4,
                                                                  run_type => 'Paired End Read 2',
                                                                  gerald_directory => $gerald_directory,
                                                              );
isa_ok($instrument_data,'Genome::InstrumentData::Solexa');
$instrument_data->set_always('dump_illumina_fastq_archive',$instrument_data->gerald_directory);

my $r = Genome::InstrumentData::Solexa::Report::Quality->create(
    instrument_data_id => $instrument_data->id,
);
ok($r, "created a new report");

my $v = $r->generate_report;
ok($v, "generation worked");

my $result = $v->save($tmp);
ok($result, "saved to $tmp");

my $name = $r->name;
$name =~ s/ /_/g;

ok(-d "$tmp/$name", "report directory $tmp/$name is present");
ok(-e "$tmp/$name/report.xml", 'xml report is present');



