#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{GENOME_SOFTWARE_RESULT_TEST_NAME} = 'tmooney-testcase-mimic-short-build';
};

use above 'Genome';
use Test::More tests => 4;

use_ok('Genome::Model::Tools::DetectVariants2::Result::Combine::LqUnion');

my $test_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-DetectVariants2-Combine-LqUnion';

#This is from the somatic-variation short test. Consider creating dummy data!
my $hq_result = Genome::SoftwareResult->get(116186269);

my @results;
my @to_process = ($hq_result);
while(my $r = shift @to_process) {
    push @results, $r;
    my @u = map($_->software_result, Genome::SoftwareResult::User->get(user_id => $r->id, user_class_name => $r->class));
    push @to_process, grep($_->isa('Genome::Model::Tools::DetectVariants2::Result::Base'), @u);
}

is(scalar(@results), 6, 'found all expected results for union')
    or diag('found: ' . join(' ' , map($_->class . ':' . $_->id, @results)));

my $lq = Genome::Model::Tools::DetectVariants2::Result::Combine::LqUnion->create(
    result_ids => [map($_->id, @results)],
    variant_type => 'snv',
    test_name => $ENV{GENOME_SOFTWARE_RESULT_TEST_NAME} || undef,
);
isa_ok($lq, 'Genome::Model::Tools::DetectVariants2::Result::Combine::LqUnion', 'generated_result');

my $expected = join('/', $test_dir, 'snvs.lq.bed');
my $actual = $lq->path('snvs.lq.bed');

ok(!Genome::Sys->diff_file_vs_file($expected, $actual), 'result matches expected output')
    or diag("diff:\n" . Genome::Sys->diff_file_vs_file($expected, $actual));
