use strict;
use warnings;

use Workflow;

use Bio::Seq;
use Bio::SeqIO;

use File::Temp;
use Test::More tests => 53;

BEGIN {
    use_ok('PAP::Command');
    use_ok('PAP::Command::InterProScan');
}

my $command = PAP::Command::InterProScan->create('fasta_file' => 'data/B_coprocola.chunk.fasta');
isa_ok($command, 'PAP::Command::InterProScan');

ok($command->execute());

my $ref = $command->bio_seq_feature();

is(ref($ref), 'ARRAY');

foreach my $feature (@{$ref}) {

    isa_ok($feature, 'Bio::SeqFeature::Generic');

    my $annotation_collection = $feature->annotation();

    isa_ok($annotation_collection, 'Bio::Annotation::Collection');

}
