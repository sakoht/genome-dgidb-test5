#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;
use above "Genome";
use File::Slurp;

BEGIN {
    use_ok("Genome::Model::Report::Pfam");
}

my $build_id = 93293206;
my $build = Genome::Model::Build->get(build_id => $build_id);
ok($build, "got a build");

my ($id, $name) = ($build_id,'Pfam');

#my $model_id = 2733662090; #2661729970;
#$report->_process_coding_transcript_file('Pfam.t.dat');

my $p = Genome::Model::Report->create(
                                            build_id => $build_id,
                                            #model_id => $model_id,
                                            name     => 'Pfam'
                                           );

# is this a "Genome::Model::Report::Pfam" object?
is(ref($p), 'Genome::Model::Report::Pfam');

my $snpstestfile = "snpfiletest.pfam.dat";
my $testoutput = "testoutput.snps.dat";
my $readonly_testfile = "readonly.snps.dat";
my @lines = read_file($snpstestfile);

# test creating the snps dat list file
ok($p->_create_snpsdat_file(\@lines, $testoutput), 'can write out file');
unlink $testoutput;

write_file($readonly_testfile, ('blah'));
chmod 0444, $readonly_testfile;
ok($p->_create_snpsdat_file(\@lines, $readonly_testfile) eq 0, 'test for failure on writing file out');
chmod 0644, $readonly_testfile;
unlink $readonly_testfile;

$p = undef;

SKIP: {
    skip "need to set environment variable to run iprscan", 1 unless $ENV{RUNIPRSCAN} eq 1;
# test checking the transcripts/getting the peps/prots.
    $p = Genome::Model::Report->create(
                                          build_id      => $build_id,
                                         #model_id     => $model_id,
                                         name         => 'Pfam',
                                         test_no_load => 1,
                                        );
    my $coding_ts_file = "pfam_coding_transcript_data.dat";
    ok($p->_process_coding_transcript_file($coding_ts_file),'processing coding transcript annotation file');

    foreach my $file ((".snps.dat",".gff",".pep.fasta",".transcript_names"))
    {
        unlink $coding_ts_file . $file;
    }

} # end skip
$p = undef;

$p = Genome::Model::Report->create(
                                        build_id => $build_id,
                                         #model_id     => $model_id,
                                         name         => 'Pfam',
                                         test_no_load => 1,
                                        );

my $test_report = "pfam_test_report.csv";
my $test_snpsdat_report = "pfam_test_report.snps.dat";
ok($p->_run_report($test_snpsdat_report, $test_report),'test running the report');

# should check the output...
my @comparison1 = read_file("pfam_test_report.comparison");
my @comparison2 = read_file($test_report);
is_deeply(\@comparison2,\@comparison1, 'report contents match');
unlink $test_report;

$p = undef;
# test full run of the generate_report_detail method.

$p = Genome::Model::Report->create(
                                        build_id => $build_id,
                                         #model_id     => $model_id,
                                         name         => 'Pfam',
                                         test_no_load => 1,
                                        );

SKIP: {
    skip "need to set environment variable to run iprscan", 1 unless $ENV{RUNIPRSCAN} eq 1;
ok($p->generate_report_detail(report_detail => "full_report_test.csv"),'run a full report via generate_report_detail()');
unlink "full_report_test.csv";
} # end skip
