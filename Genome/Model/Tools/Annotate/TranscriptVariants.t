#!/gsc/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 9;
use File::Compare;
use above "Genome";

my $test_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Annotate-TranscriptVariants';

ok(-d $test_dir, "test data dir exists");

my $input = "$test_dir/input";

ok(-e $input, 'input exists');

my $ref_transcript = "$test_dir/known_output.transcript";
ok(-e $ref_transcript, 'ref transcript exists');

my $output_base = "$test_dir/output";
my $command = Genome::Model::Tools::Annotate::TranscriptVariants->create(
    variant_file => $input,
    output_file => "$output_base.transcript",
);
is($command->execute(),1, "executed transcript variants w/ return value of 1");

my $transcript = "$output_base.transcript";
ok(-e $transcript, 'transcript output exists');

SKIP: {
    skip 'skipping comparison until default behavior is settled', 1;
is(compare($transcript, $ref_transcript), 0, "transcript and ref transcript are the same")
    or diag(`sdiff $transcript $ref_transcript`);
}

unlink($transcript);

my $command_reference_transcripts = Genome::Model::Tools::Annotate::TranscriptVariants->create(
    reference_transcripts => "NCBI-human.ensembl/54_36p",
    variant_file => $input,
    output_file => "$output_base.transcript",
);
is($command_reference_transcripts->execute(),1, "executed transcript variants with reference transcripts w/ return value of 1");

SKIP: {
   skip 'skipping for warnings', 2;

my $command_build_id = Genome::Model::Tools::Annotate::TranscriptVariants->create(
    build_id => 96232344,
    variant_file => $input,
    output_file => "$output_base.transcript",
);
is($command_build_id->execute(),1, "executed transcript variants with build id w/ return value of 1");

$command_reference_transcripts = Genome::Model::Tools::Annotate::TranscriptVariants->create(
    reference_transcripts => "NCBI-human.ensembl/54_36p",
    variant_file => $input,
    output_file => "$output_base.transcript",
);
is($command_reference_transcripts->execute(),1, "executed transcript variants with reference transcripts w/ return value of 1");

$command_reference_transcripts = Genome::Model::Tools::Annotate::TranscriptVariants->create(
    reference_transcripts => "NCBI-human.ensembl/54_36p",
    variant_file => $input,
    output_file => "$output_base.transcript",
);
is($command_reference_transcripts->execute(),1, "executed transcript variants with reference transcripts w/ return value of 1");
}
