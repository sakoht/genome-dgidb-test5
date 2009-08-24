#!/gsc/bin/perl

use strict;
use warnings;

use above 'Genome';
use Test::More tests => 2;


BEGIN {use_ok('Genome::Model::Tools::ViromeEvent::CDHIT::RemoveFile');}

#create
my $rf = Genome::Model::Tools::ViromeEvent::CDHIT::RemoveFile->create(
                                                                dir => '/gscmnt/sata835/info/medseq/virome/test_mini/S0_Mouse_Tissue_0_Control',
                                                            );
isa_ok($rf, 'Genome::Model::Tools::ViromeEvent::CDHIT::RemoveFile');
#$rf->execute();
