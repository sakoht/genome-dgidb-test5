#!/gsc/bin/perl

use strict;
use warnings;

use above 'Genome';
use Test::More tests => 2;


BEGIN {use_ok('Genome::Model::Tools::ViromeEvent::BlastN::OuterCheckOutput');}

#create
my $co = Genome::Model::Tools::ViromeEvent::BlastN::OuterCheckOutput->create(
                                                                dir => '/gscmnt/sata835/info/medseq/virome/test17/S0_Mouse_Tissue_0_Control',
                                                                logfile => '/gscmnt/sata835/info/medseq/virome/test17/logfile.txt',
                                                            );
isa_ok($co, 'Genome::Model::Tools::ViromeEvent::BlastN::OuterCheckOutput');
$co->execute();
my $arr = $co->files_for_blast;
print @$arr;
foreach my $file(@$arr)
{
   print "$file\n" ;
}
