#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";

use Bio::SeqIO;
use Test::More;

my $display_id = 'S000002017 Pirellula staleyi';
my $seq_str = 'AATGAACGTTGGCGGCATGGATTAGGCATGCAAGTCGTGCGCGATATGTAGCAATACATGGAGAGCGGCGAAAGGGAGAGTAATACGTAGGAACCTACCTTCGGGTCTGGGATAGCGGCGGGAAACTGCCGGTAATACCAGATGATGTTTCCGAACCAAAGGTGTGATTCCGCCTGAAGAGGGGCCTACGTCGTATTAGCTAGTTGGTAGGGTAATGGCCTACCAAGnCAAAGATGCGTATGGGGTGTGAGAGCATGCCCCCACTCACTGGGACTGAGACACTGCCCAGACACCTACGGGTGGCTGCAGTCGAGAATCTTCGGCAATGGGCGAAAGCCTGACCGAGCGATGCCGCGTGCGGGATGAAGGCCTTCGGGTTGTAAACCGCTGTCGTAGGGGATGAAGTGCTAGGGGGTTCTCCCTCTAGTTTGACTGAACCTAGGAGGAAGGnCCGnCTAATCTCGTGCCAGCAnCCGCGGTAATACGAGAGGCCCAnACGTTATTCGGATTTACTGGGCTTAAAGAGTTCGTAGGCGGTCTTGTAAGTGGGGTGTGAAATCCCTCGGCTCAACCGAGGAACTGCGCTCCAnACTACAAGACTTGAGGGGGATAGAGGTAAGCGGAACTGATGGTGGAGCGGTGAAATGCGTTGATATCATCAGGAACACCGGAGGCGAAGGCGGCTTACTGGGTCCTTTCTGACGCTGAGGAACGAAAGCTAGGGGAGCAnACGGGATTAGATACCCCGGTAGTCCTAnCCGTAAACGATGAGCACTGGACCGGAGCTCTGCACAGGGTTTCGGTCGTAGCGAAAGTGTTAAGTGCTCCGCCTGGGGAGTATGGTCGCAAGGCTGAAACTCAAAGGAATTGACGGGGGCTCACACAAGCGGTGGAGGATGTGGCTTAATTCGAGGCTACGCGAAGAACCTTATCCTAGTCTTGACATGCTTAGGAATCTTCCTGAAAGGGAGGAGTGCTCGCAAGAGAGCCTnTGCACAGGTGCTGCATGGCTGTCGTCAGCTCGTGTCGTGAGATGTCGGGTTAAGTCCCTTAACGAGCGAAACCCTnGTCCTTAGTTACCAGCGCGTCATGGCGGGGACTCTAAGGAGACTGCCGGTGTTAAACCGGAGGAAGGTGGGGATGACGTCAAGTCCTCATGGCCTTTATGATTAGGGCTGCACACGTCCTACAATnGTGCACACAAAGCGACGCAAnCTCGTGAGAGCCAGCTAAGTTCGGATTGCAGGCTGCAACTCGCCTGCATGAAGCTGGAATCGCTAGTAATCGCGGGTCAGCATACCGCGGTGAATGTGTTCCTGAGCCTTGTACACACCGCCCGTCAAGCCACGAAAGTGGGGGGGACCCAACAGCGCTGCCGTAACCGCAAGGAACAAGGCGCCTAAGGTCAACTCCGTGATTGGGACTAAGTCGTAACAAGGTAGCCGTAGGGGAACCTGCGGCTGGATCACCTCCTT';

my $rev_str = scalar reverse $seq_str;
my $seq = Bio::Seq->new( 
    -display_id => $display_id,
    -seq => $seq_str,
);

my $rev_seq = $seq->revcom();

my $training_set = '4'; #(4,6,broad)

#list versions
my $classifier = Genome::Utility::MetagenomicClassifier::Rdp::Version2x1->new(training_set => $training_set);

ok($classifier, 'Created rdp classifier');
my $version = $classifier->get_training_version;
ok ($version ne '', 'Got training set version');

my $classification = $classifier->classify($seq);
ok($classification, 'got classification from classifier');
isa_ok($classification, 'Genome::Utility::MetagenomicClassifier::SequenceClassification');
my $taxon = $classification->get_taxon;
do {
    ($taxon) = $taxon->each_Descendent;
} until ($taxon->is_Leaf()); 
ok($taxon->id eq 'Pirellula', 'found correct classification');

my ($conf) = $taxon->get_tag_values('confidence');
ok($conf == 1.0, 'found correct confidence value');

my $is_reversed = $classifier->is_reversed($rev_seq);
ok ($is_reversed, 'reverse correctly identified');

# classify fails
eval{ $classifier->classify(); };
diag($@);
like($@, qr(No sequence given to classify), 'fail to classify w/ undef sequence');
ok(!$classifier->classify( Bio::Seq->new(-id => 'Short Seq', -seq => 'A') ), 'fail to classify short sequence');

done_testing();
exit;

#$HeadURL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/Genome/Utility/MetagenomicClassifier/Rdp.t $
#$Id: Rdp.t 57677 2010-04-16 17:31:32Z edemello $
