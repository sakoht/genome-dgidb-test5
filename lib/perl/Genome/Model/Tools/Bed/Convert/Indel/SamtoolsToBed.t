#!/gsc/bin/perl

use strict;
use warnings;

use Test::More tests => 5;

use above 'Genome';

use_ok('Genome::Model::Tools::Bed::Convert::Indel::SamtoolsToBed');

my $tmpdir = File::Temp::tempdir('Bed-Convert-Indel-SamtoolsToBedXXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites/', CLEANUP => 1);
my $output_file = join('/', $tmpdir, 'output');

my $input_file = __FILE__ . '.input';
my $expected_file = __FILE__ . '.expected';

my $command = Genome::Model::Tools::Bed::Convert::Indel::SamtoolsToBed->create( source => $input_file, output => $output_file );
ok($command, 'Command created');
my $rv = $command->execute;
ok($rv, 'Command completed successfully');
ok($command->_need_chrom_sort, 'unordered chromosomes in input detected');

my $diff = Genome::Utility::FileSystem->diff_file_vs_file($output_file, $expected_file);
ok(!$diff, 'output matched expected result')
    or diag("diff results:\n" . $diff);
