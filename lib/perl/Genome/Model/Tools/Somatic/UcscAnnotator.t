#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use Test::More tests => 3;
use Data::Dumper;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

BEGIN {
    use_ok( 'Genome::Model::Tools::Somatic::UcscAnnotator');
};

my $input_file = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-Somatic-UcscAnnotator/input_test_file.txt";
my $expected_output = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-Somatic-UcscAnnotator/expected_output_file.txt";
my $output_file = Genome::Utility::FileSystem->create_temp_file_path;
my $unannotated_file = Genome::Utility::FileSystem->create_temp_file_path;

my $ucsc_annotator = Genome::Model::Tools::Somatic::UcscAnnotator->create(input_file=>$input_file, output_file=>$output_file, unannotated_file=>$unannotated_file);
ok ($ucsc_annotator, "created ucsc_annotator");
ok ($ucsc_annotator->execute(), "executed ucsc_annotator");


my $diff = `diff $output_file $expected_output`;  ##Some annotation is expected to change over time if this part of the test fails we'll need to look at the output_file
#ok($diff eq '', "no differences");


