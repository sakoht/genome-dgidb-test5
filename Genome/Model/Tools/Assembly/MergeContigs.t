#!/gsc/bin/perl

use strict;
use warnings;
use above 'Genome';
use Genome;

use Genome::Model::Tools::Assembly::MergeContigs;

use Test::More tests => 1;
#use Test::More skip_all => "Test data not in place yet.";

my $contigs = 'merge.ace contig00012.0 merge.ace contig00013.1';
my $path = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Assembly-MergeContigs/edit_dir';

my $output_file_name = 'out.ace';
chdir($path);
system "/bin/rm -f *.db";
ok(Genome::Model::Tools::Assembly::MergeContigs->execute(contigs => $contigs, o => $output_file_name, cc => 1), "MergeContigs executed successfully");
#my @lines = `/gscuser/jschindl/bin/acecheck out.ace`;print @lines;
#ok(($lines[-1] =~ /parsed correctly/), "Ace file is syntactically correct");
