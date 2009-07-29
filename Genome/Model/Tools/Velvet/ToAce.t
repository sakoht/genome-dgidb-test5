#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use File::Temp;
use Test::More tests => 4;

BEGIN {
    use_ok('Genome::Model::Tools::Velvet::ToAce');
}

my $root_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Velvet/ToAce';
my $file = $root_dir.'/velvet_asm.afg';
my $ori_ace = $root_dir.'/velvet_asm.ace';

my $tmp_dir = File::Temp::tempdir(
    'ToAce_XXXXXX', 
    DIR     => $root_dir,
    CLEANUP => 1,
);

my $out_ace = $tmp_dir.'/velvet_asm.ace';

my $ta = Genome::Model::Tools::Velvet::ToAce->create(
    afg_file    => $file,
    out_acefile => $out_ace,
    time        => 'Wed Jul 29 10:59:26 2009',
);

ok($ta, 'to-ace creates ok');
ok($ta->execute, 'velvet to-ace runs ok');

my @diff = `diff $out_ace $ori_ace`;

my $pass = 0;
$pass++ if $diff[1] =~ /comment\sVelvetToAce/ and $diff[3] =~/comment\sVelvetToAce/ and scalar @diff == 4;

ok($pass, 'Ace file converted from velvet output is OK');

exit;
