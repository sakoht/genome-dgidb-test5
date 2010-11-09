use strict;
use warnings;

use above 'Genome';

use Bio::Seq;
use Bio::SeqIO;

use File::Temp 'tempdir';
use File::Basename;
use Test::More tests => 9;

BEGIN {
    use_ok('Genome::Model::Tools::GenePredictor');
    use_ok('Genome::Model::Tools::GenePredictor::RNAmmer');
}

my $test_dir = "/gsc/var/cache/testsuite/running_testsuites/";
my $test_output_dir = tempdir('Genome-Model-Tools-GenePredictor-SNAP-XXXXXX',
    DIR => $test_dir,
    CLEANUP => 1,
    UNLINK => 1,
);
chmod(0755, $test_output_dir);
ok(-d $test_output_dir, "test output dir exists");

my $test_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-GenePredictor/';
ok(-e $test_data_dir, "test data directory exists at $test_data_dir");

my $fasta = $test_data_dir . 'SCTG6.a_b.dna.masked.fasta';
ok(-e $fasta, "fasta file exists at $fasta");

my $command = Genome::Model::Tools::GenePredictor::RNAmmer->create(
    fasta_file => $fasta,
    raw_output_directory => $test_output_dir,
    prediction_directory => $test_output_dir,
);

isa_ok($command, 'Genome::Model::Tools::GenePredictor');
isa_ok($command, 'Genome::Model::Tools::GenePredictor::RNAmmer');
ok($command->execute(), "executed rnammer command");

my @rna = Genome::Prediction::RNAGene->get(
    directory => $test_output_dir,
);
my $num_rna = scalar @rna;
ok ($num_rna > 0, "able to retrieve $num_rna RNAGene objects");

