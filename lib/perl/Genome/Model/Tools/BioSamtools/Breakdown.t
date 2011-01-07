#!/gsc/bin/perl

use strict;
use warnings;

use Test::More tests => 5;
#use Test::More skip_all => 'Disabling due to Perl environtment issues';

use above 'Genome';
use File::Temp qw/ tempdir /;
use File::Compare;

my $test_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-BioSamtools/Breakdown';
my $bam_file = $test_data_dir .'/breakdown.bam';

my $expected_tsv = $test_data_dir .'/breakdown-64.tsv';
my $base_output_dir = tempdir('BREAKDOWN_XXXXX',DIR => '/tmp',CLEANUP=> 1);

my $cmd = Genome::Model::Tools::BioSamtools::Breakdown->create(
    output_file => $base_output_dir .'/breakdown.tsv',
    bam_file => $bam_file,
);

isa_ok($cmd,'Genome::Model::Tools::BioSamtools::Breakdown');
ok($cmd->execute,'execute breakdown command '. $cmd->command_name);
ok(-f $cmd->output_file,'found output tsv file '. $cmd->output_file);
ok(-s $cmd->output_file,'output tsv file '. $cmd->output_file .' has size');
ok(!compare($cmd->output_file,$expected_tsv),'output tsv '. $cmd->output_file .' matches expected '. $expected_tsv);

exit;
