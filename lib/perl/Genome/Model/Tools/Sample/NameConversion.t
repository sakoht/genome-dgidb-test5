#!/gsc/bin/perl
use strict;
use warnings;
use above 'Genome';
use Test::More tests => 5;

my $input = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-Sample-NameConversion/test.in";
ok(-e $input, 'Input file exists');

my $output = Genome::Utility::FileSystem->create_temp_file_path("out"); #"/gsc/var/cache/testsuite/data/Genome-Model-Tools-Sample-NameConversion/test.out";
my $expected_output = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-Sample-NameConversion/expected.test.out";
ok(-e $expected_output, 'Expected output file exists');

my $conversion = Genome::Model::Tools::Sample::NameConversion->execute(input=>$input,output=>$output,short_to_long=>"1");
ok($conversion, 'Executed a NameConversion object');

ok(-e $output, 'Output file exists');

my $diff = `diff $output $expected_output`;
ok($diff eq '', "output as expected");

