#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';
use Test::More tests => 17;

use_ok('Genome::Model::Tools::Vcf::VcfToVariantMatrix');

my $test_dir = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-Vcf-Vcf-To-Variant-Matrix/";
my $input_file = "$test_dir/vcf-to-variant-matrix.test.input";


my $output_file = Genome::Sys->create_temp_file_path;

###################################################################
my $bases_transposed_expected_output_file ="$test_dir/vcf-to-variant-matrix.test.transposed.output";
my $command = Genome::Model::Tools::Vcf::VcfToVariantMatrix->create( vcf_file=> $input_file,
                                                                     output_file=>$output_file,
                                                                     transpose=>1,
                                                                 );
ok($command, 'Command created');
my $rv = $command->execute;
ok($rv, 'Command completed Successfully');
ok(-s $output_file, "output_file_created");

my $diff = Genome::Sys->diff_file_vs_file($output_file, $bases_transposed_expected_output_file);
ok(!$diff, 'output matched expected result')
    or diag("diff results:\n" . $diff);
###################################################################
my $bases_expected_output_file ="$test_dir/vcf-to-variant-matrix.test.output";

my $output_file = Genome::Sys->create_temp_file_path;


my $command = Genome::Model::Tools::Vcf::VcfToVariantMatrix->create( vcf_file=> $input_file,
                                                                     output_file=>$output_file
                                                                 );
ok($command, 'Command created');
my $rv = $command->execute;
ok($rv, 'Command completed Successfully');
ok(-s $output_file, "output_file_created");

my $diff = Genome::Sys->diff_file_vs_file($output_file, $bases_expected_output_file);
ok(!$diff, 'output matched expected result')
    or diag("diff results:\n" . $diff);
###################################################################
my $numerical_transposed_expected_output_file ="$test_dir/vcf-to-variant-matrix.test.numerical.transposed.output";

my $output_file = Genome::Sys->create_temp_file_path;


my $command = Genome::Model::Tools::Vcf::VcfToVariantMatrix->create( vcf_file=> $input_file,
                                                                     output_file=>$output_file,
                                                                     transpose=>1,
                                                                     matrix_genotype_version=>"numerical",
                                                                 );
ok($command, 'Command created');
my $rv = $command->execute;
ok($rv, 'Command completed Successfully');
ok(-s $output_file, "output_file_created");

my $diff = Genome::Sys->diff_file_vs_file($output_file, $numerical_transposed_expected_output_file);
ok(!$diff, 'output matched expected result')
    or diag("diff results:\n" . $diff);
###################################################################
my $numerical_expected_output_file ="$test_dir/vcf-to-variant-matrix.test.numerical.output";
my $output_file = Genome::Sys->create_temp_file_path;
my $command = Genome::Model::Tools::Vcf::VcfToVariantMatrix->create( vcf_file=> $input_file,
                                                                     output_file=>$output_file,
                                                                     matrix_genotype_version=>"numerical",
                                                                 );
ok($command, 'Command created');
my $rv = $command->execute;
ok($rv, 'Command completed Successfully');
ok(-s $output_file, "output_file_created");

my $diff = Genome::Sys->diff_file_vs_file($output_file, $numerical_expected_output_file);
ok(!$diff, 'output matched expected result')
    or diag("diff results:\n" . $diff);



