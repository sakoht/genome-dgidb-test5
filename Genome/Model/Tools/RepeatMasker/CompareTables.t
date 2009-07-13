#!/gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

use Test::More tests => 4;
use File::Compare;

BEGIN {
      use_ok('Genome::Model::Tools::RepeatMasker::CompareTables');
};
my $root_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-RepeatMasker/MergeTables';
my @lanes = qw(3 4);
my @tables;
for my $lane (@lanes) {
    push @tables, $root_dir .'/s_'. $lane .'_sequence.fa.tsv';
}
my $expected_file = $root_dir .'/compare.tsv';


my $tmp_dir = File::Temp::tempdir('RepeatMasker-CompareTables-'. $ENV{USER} .'-XXXX',DIR=>'/gsc/var/cache/testsuite/running_testsuites',CLEANUP=>1);
my $merged_file = $tmp_dir .'/compare.tsv';
my $merge = Genome::Model::Tools::RepeatMasker::CompareTables->create(
    input_tables => \@tables,
    output_table => $merged_file,
);
isa_ok($merge,'Genome::Model::Tools::RepeatMasker::CompareTables');
ok($merge->execute,'execute command '. $merge->command_name);
ok(!compare($merged_file,$expected_file),'files are identical');
exit;
