BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

use_ok('Genome::Model::Tools::Fasta::SortByName') or die;

my $test_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Fasta/';
ok(-d $test_data_dir, "test data dir existst at $test_data_dir");

my $test_output_dir = '/gsc/var/cache/testsuite/running_testsuites/';
ok(-d $test_output_dir, "test output dir exists at $test_output_dir");

my $unsorted = $test_data_dir . 'file_two_seq.fasta';
ok(-e $unsorted, "unsorted input fasta exists at $unsorted");

my $expected = $test_data_dir . 'file_two_seq.fasta.sorted';
ok(-e $expected, "expected output file exists at $expected");

my $output_fh = File::Temp->new(
    DIR => $test_output_dir,
    TEMPLATE => 'genome-model-tools-fasta-sortbyname-XXXXXX',
);
my $output = $output_fh->filename;
ok($output, "output will go into $output");

my $cmd = Genome::Model::Tools::Fasta::SortByName->create(
    input_fasta => $unsorted,
    sorted_fasta => $output,
);
ok($cmd, 'made fasta sorter command object');

ok($cmd->execute, 'executed sorter');

my $reader = Genome::Data::IO::Reader->create(
    file => $output,
    format => 'fasta',
);

my $expected_reader = Genome::Data::IO::Reader->create(
    file => $expected,
    format => 'fasta',
);

while (my $seq = $reader->next) {
    my $expected_seq = $expected_reader->next;
    ok($expected_seq, "got expected seq from file");
    ok($expected_seq->sequence_name eq $seq->sequence_name, "expected seq " . $expected_seq->sequence_name .
        " matches generated seq name " . $seq->sequence_name);
}
ok(!$expected_reader->next, 'expected file has no extra sequences');

done_testing();

