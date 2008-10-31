#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use Test::More tests => 5;

BEGIN {
        use_ok('Genome::Model::Tools::BioDbFasta::Convert');
}

my $infile_nonexist = "/blah/not/exists";
my $outfile = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BioDbFasta/Convert/testoutput1";
my $infile_test = "/gsc/var/cache/testsuite/data/Genome-Model-Tools-BioDbFasta/Convert/testinput1";

my $c_f_noexist = Genome::Model::Tools::BioDbFasta::Convert->create('infile' => $infile_nonexist  ,
                                                          'outfile' =>  $outfile );

isa_ok($c_f_noexist,'Genome::Model::Tools::BioDbFasta::Convert');

is($c_f_noexist->execute(),0,'infile non-existent');

my $c =  Genome::Model::Tools::BioDbFasta::Convert->create('infile' => $infile_test ,
                                                          'outfile' =>  $outfile );

ok($c->execute(),'running on test file 1');

my $c_test_gqs = Genome::Model::Tools::BioDbFasta::Convert->create('infile' => $infile_test ,
                                                          'outfile' =>  $outfile );

my $string = $c_test_gqs->getQualString("55 33 55 55 10 29 34");
is($string,'XBXX+=C','getQualString');
