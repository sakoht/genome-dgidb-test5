#!/gsc/bin/perl

use strict;
use warnings;
use Test::More tests => 20;
use Genome::Info::IUB;

#Test variant_alleles_for_iub
is(Genome::Info::IUB::variant_alleles_for_iub(undef, undef),undef, "variant_alleles_for_iub: undefined inputs return undef");  #test to make sure it handles undefined values
is(Genome::Info::IUB::variant_alleles_for_iub(undef, 'A'), undef, "variant_alleles_for_iub: undefined ref returns undef");
is(Genome::Info::IUB::variant_alleles_for_iub('A', undef),undef, "variant_alleles_for_iub: undefined iub returns undef");
is(Genome::Info::IUB::variant_alleles_for_iub('N', 'A'), undef, "variant_alleles_for_iub: ambiguous ref returns undef");
is(Genome::Info::IUB::variant_alleles_for_iub('Q', 'A'), undef, "variant_alleles_for_iub: invalid ref returns undef");
is(Genome::Info::IUB::variant_alleles_for_iub('G', 'Q'), undef, "variant_alleles_for_iub: invalid iub returns undef");
my @alleles = Genome::Info::IUB::variant_alleles_for_iub('G','W');
is_deeply(\@alleles, ['A','T'] , "variant_alleles_for_iub: returns values on proper input");



is(Genome::Info::IUB::iub_for_alleles(undef),undef, "iub_for_alleles: undefined inputs return undef");  #test to make sure it handles undefined values
is(Genome::Info::IUB::iub_for_alleles('A'), undef, "iub_for_alleles: invalid input returns undef");
is(Genome::Info::IUB::iub_for_alleles('A','T','G'),undef, "iub_for_alleles: unsupported input return undef");
is(Genome::Info::IUB::iub_for_alleles('A','N'), undef, "iub_for_alleles: invalid nucleotides return undef");
is(Genome::Info::IUB::iub_for_alleles('a','T'), 'W', "iub_for_alleles: case insensitivity and valid result");


is(Genome::Info::IUB::iub_to_alleles(undef),undef, "iub_to_alleles: undefined inputs return undef");  #test to make sure it handles undefined values
is(Genome::Info::IUB::iub_to_alleles('Q'), undef, "iub_to_alleles: invalid input returns undef");
is_deeply([Genome::Info::IUB::iub_to_alleles('A')],['A','A'], "iub_to_alleles: returns two alleles for homozygote");
@alleles = sort(Genome::Info::IUB::iub_to_alleles('w'));
is_deeply(\@alleles, ['A','T'], "iub_to_alleles: case insensitivity and valid result");


is(Genome::Info::IUB::iub_to_bases(undef),undef, "iub_to_bases: undefined inputs return undef");  #test to make sure it handles undefined values
is(Genome::Info::IUB::iub_to_bases('Q'), undef, "iub_to_bases: invalid input returns undef");
is_deeply([Genome::Info::IUB::iub_to_bases('A')],['A'], "iub_to_bases: returns one base for homozygote");
my @bases = sort(Genome::Info::IUB::iub_to_bases('w'));
is_deeply(\@bases, ['A','T'], "iub_to_bases: case insensitivity and valid result");

#$HeadURL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/Genome/Info/CodonToAminoAcid.pm $
#$Id: CodonToAminoAcid.pm 34977 2008-05-23 22:34:14Z ebelter $
