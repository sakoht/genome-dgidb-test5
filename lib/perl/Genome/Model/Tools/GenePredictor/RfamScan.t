use strict;
use warnings;

use above 'Genome';

use Bio::Seq;
use Bio::SeqIO;

use File::Temp 'tempdir';
use File::Basename;
use Test::More skip_all => 'Takes an hour, regardless of input sequence size';

BEGIN {
    use_ok('Genome::Model::Tools::GenePredictor');
    use_ok('Genome::Model::Tools::GenePredictor::RfamScan');
}

my $test_dir = "/gsc/var/cache/testsuite/running_testsuites/";
my $test_output_dir = tempdir('Genome-Model-Tools-GenePredictor-Rfamscan-XXXXXX',
    DIR => $test_dir,
    CLEANUP => 1,
    UNLINK => 1,
);
chmod(0755, $test_output_dir);
ok(-d $test_output_dir, "test output dir exists");

my $test_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-GenePredictor/';
my $fasta = $test_data_dir . 'Contig0a.masked.fasta.short';
ok(-e $fasta, "fasta file exists at $fasta");

my $command = Genome::Model::Tools::GenePredictor::RfamScan->create(
    fasta_file => $fasta,
    prediction_directory => $test_output_dir,
    raw_output_directory => $test_output_dir,
);

isa_ok($command, 'Genome::Model::Tools::GenePredictor');
isa_ok($command, 'Genome::Model::Tools::GenePredictor::RfamScan');

ok($command->execute(), "executed rfamscan command");

my @rna = Genome::Prediction::RNAGene->get(
    directory => $test_output_dir,
);
my $num_rna = scalar @rna;
ok($num_rna > 0, "able to retrieve $num_rna RNAGene objects");

