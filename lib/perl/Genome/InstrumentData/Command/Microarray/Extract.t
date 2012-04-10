#! /gsc/bin/perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';

use Data::Dumper;
require File::Temp;
require File::Compare;
require Test::MockObject;
use Test::More;

use_ok('Genome::InstrumentData::Command::Microarray::Extract') or die;


my $testdir = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Command-Microarray';
my $dbsnp_file = $testdir.'/dbsnp.132';
my $expected_output = $testdir.'/expected.output';
my $fl = Genome::Model::Tools::DetectVariants2::Result::Manual->__define__(
    description => '__TEST__DBSNP132__',
    username => 'apipe-tester',
    file_content_hash => 'c746fb7b7a88712d27cf71f8262dd6e8',
    output_dir => $testdir,
);
ok($fl, 'create dv2 result');
my $variation_list_build = Genome::Model::Build::ImportedVariationList->__define__(
    model => Genome::Model->get(2868377411),
    snv_result => $fl,
    version => 132,
);
ok($variation_list_build, 'create variation list build');

my $sample = Genome::Sample->__define__(
    name => '__TEST__SAMPLE__',
);
ok($sample, 'create sample');
my $library = Genome::Library->__define__(
    name => $sample->name.'-microarraylib',
    sample => $sample,
);
ok($library, 'create library');
my $instrument_data = Genome::InstrumentData::Imported->__define__(
    id => -7777,
    library => $library,
    import_format => 'genotype file',
    sequencing_platform => 'infinium',
);
ok(
    $instrument_data->add_attribute(attribute_label => 'genotype_file', attribute_value => $testdir.'/snpreport/-7777'),
    'add attr to inst data for genotype file',
);
ok($instrument_data, 'create instrument data');
$sample->default_genotype_data_id($instrument_data->id);

no warnings;
*Genome::FeatureList::file_path = sub{ return $dbsnp_file };
use warnings;

my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
my $output = $tmpdir.'/genotypes.out';

my $cmd = Genome::InstrumentData::Command::Microarray::Extract->create(
    output => $output,
    sample => $sample,
    filters => [qw/ gc_score:min=0.7 /],
    fields => [qw/ chromosome position alleles id /],
    variation_list_build => $variation_list_build,
    use_default => 1,
);
ok($cmd, 'create');
$cmd->dump_status_messages(1);
ok($cmd->execute, 'execute');
is(File::Compare::compare($output, $expected_output), 0, 'output file matches');

done_testing();
exit;

