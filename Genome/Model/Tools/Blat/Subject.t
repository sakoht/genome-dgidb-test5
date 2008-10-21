#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";

use Test::More tests => 7;

BEGIN {
        use_ok('Genome::Model::Tools::Blat::Subject');
}

my $query_file = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Blat-Subject/test.fa';
ok(-s $query_file,'query file has size');

my $subject_file = '/gscmnt/839/info/medseq/reference_sequences/refseq-for-test/11.fa';
ok(-s $subject_file,'subject file has size');

my $blat = Genome::Model::Tools::Blat::Subject->create(
                                                    query_file => $query_file,
                                                    subject_file => $subject_file,
                                                );

isa_ok($blat,'Genome::Model::Tools::Blat::Subject');
ok($blat->execute,'execute command '. $blat->command_name);
ok($blat->alignment_file =~ /\/test_11\.psl$/,'expected alignment file');
ok(-s $blat->alignment_file,'alignment file has size');

exit;
