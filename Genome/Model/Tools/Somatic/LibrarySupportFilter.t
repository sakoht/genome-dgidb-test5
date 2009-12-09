#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use File::Temp;
use Test::More tests => 6;
use Data::Dumper;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

BEGIN {
    use_ok( 'Genome::Model::Tools::Somatic::LibrarySupportFilter');
};

my $indel_file = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-Somatic-LibrarySupportFilter/sniper.indels.txt";

my $test_output_dir = File::Temp::tempdir('Genome-Model-Tools-Somatic-LibrarySupportFilter-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);

my $multi_lib_output_file = $test_output_dir . "multi_lib.output.txt";
my $single_lib_output_file = $test_output_dir . "single_lib.output.txt";

my $library_support_filter = Genome::Model::Tools::Somatic::LibrarySupportFilter->create(
    indel_file => $indel_file,
    multi_lib_output_file => $multi_lib_output_file,
    single_lib_output_file => $single_lib_output_file,
    preferred_output_file => "", #parameter will be overwritten by execution
);

ok($library_support_filter, "created LibrarySupportFilter object");
ok($library_support_filter->execute(), "executed LibrarySupportFilter");

ok(-s $single_lib_output_file,'Single library output file created');
ok(-e $multi_lib_output_file,'Multi-library output file created'); #Okay even if empty

if(-s $multi_lib_output_file) {
    is($library_support_filter->preferred_output_file, $multi_lib_output_file, "Multi-library output has size and preferred output file set to multi-library.");
} else {
    is($library_support_filter->preferred_output_file, $single_lib_output_file, "Multi-library output has no size and preferred output file set to single library.");
}
