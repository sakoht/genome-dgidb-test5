#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use Test::More tests => 1;

BEGIN {
        use_ok('Genome::Model::Tools::BioDbFasta::Subsequence');
}

my $bad_index = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BioDbFasta/Subsequence/bad-index";
my $no_index = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BioDbFasta/Subsequence/not-indexed";
my $indexed = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BioDbFasta/Subsequence/sequence";

my $start = 1;
my $stop = 5;
my $name = "seq1";


my $s_bi = Genome::Model::Tools::BioDbFasta::Subsequence->create(
                                                                 dir => $bad_index,
                                                                 name => $name,
                                                                 start => $start,
                                                                 stop => $stop
                                                                 );

is($s_bi->execute(),0,'bad index');

my $s_noi =Genome::Model::Tools::BioDbFasta::Subsequence->create(
                                                                 dir => $no_index,
                                                                 name => $name,
                                                                 start => $start,
                                                                 stop => $stop
                                                                 );

is($s_noi->execute(),0,'no index');

my $s = Genome::Model::Tools::BioDbFasta::Subsequence->create(
                                                                 dir => $indexed,
                                                                 name => $name,
                                                                 start => $start,
                                                                 stop => $stop
                                                              );

ok($s->execute(),'indexed sequence');


my $hs_name = 'Y';
my $start1 = 100;
my $stop1 = 200;

my $s_hs36 = Genome::Model::Tools::BioDbFasta::Subsequence->create(
                                                                 dir => "hs36",
                                                                 name => $hs_name,
                                                                 start => $start1,
                                                                 stop => $stop1
                                                              );

ok($s_hs36->execute(),'hs36 as dir option');


my $s_oob = Genome::Model::Tools::BioDbFasta::Subsequence->create(
                                                                 dir => $indexed,
                                                                 name => $name,
                                                                 start => $start1,
                                                                 stop => $stop1
                                                              );

ok($s_oob->execute(),'out of bounds?');
