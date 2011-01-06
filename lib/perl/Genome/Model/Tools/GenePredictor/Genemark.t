use strict;
use warnings;

use above 'Genome';

use Bio::Seq;
use Bio::SeqIO;

use File::Temp;
use File::Basename;
use Test::More;

BEGIN {
    use_ok('Genome::Model::Tools::GenePredictor');
    use_ok('Genome::Model::Tools::GenePredictor::Genemark');
}

my $test_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-GenePredictor';
ok(-d $test_data_dir, "test data directory exists at $test_data_dir");

my $fasta_file = $test_data_dir . '/Contig0a.20kb.masked.fasta';
ok(-e $fasta_file, "test fasta file exists at $fasta_file");
ok(-s $fasta_file, "test fasta file has size at $fasta_file");

my $command = Genome::Model::Tools::GenePredictor::Genemark->create(
    fasta_file => $fasta_file, 
    gc_percent => 39.1, 
    prediction_directory => '/tmp',  # FIXME Right now, this isn't used
    raw_output_directory => '/tmp',  # FIXME Ditto... output should be placed here, though
);
isa_ok($command, 'Genome::Model::Tools::GenePredictor::Genemark');

ok($command->execute(), 'command executed');
ok($command->model_file =~ /heu_11_39\.mod$/, 'expected model file found');

my @features = @{$command->{bio_seq_feature}};
ok(@features > 0, 'bio seq features were created');

foreach my $feature (@features) {
    isa_ok($feature, 'Bio::SeqFeature::Generic');
}

done_testing();
