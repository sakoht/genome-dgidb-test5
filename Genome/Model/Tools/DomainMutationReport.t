#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use Genome::Model::Tools::DomainMutationReport;
use Test::More;
plan "skip_all";

#my $file = "/gscuser/charris/svn/pm2/Genome/Model/Tools/test.fastq";
my $file = "";
my $outfile = "";
#my $total = lines($file);

#my $size = 5;
my $dmr = Genome::Model::Tools::DomainMutationReport->create(
                                                         maf => $file,
                                                         filter => "HMMPfam",
                                                         output => $outfile,
                                                        );
ok($dmr->execute,'domain mutation report generation');

#my $sub_fastq_files_ref = $chopper->sub_fastq_files;
#my @sub_fastq_files = @$sub_fastq_files_ref;
#my $expected = (($total/4)/$size);
#is(scalar(@sub_fastq_files),$expected,'file count');


exit;

