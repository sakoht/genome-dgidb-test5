#!/gsc/bin/perl

use strict;
use warnings;
use above 'Genome';
use Genome;

use Genome::Model::Tools::Assembly::RemoveReads;

use Test::More tests => 1;

my $ace_file = 'merge.ace';
my $contig = 'contig00012.0';
my $read_list = 'FR3TRLO01AVOWP,FR3TRLO01BM88T';
my $path = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Assembly-MergeContigs/edit_dir';


my $out_file_name = 'remove_reads_out.ace';
chdir($path);
system "/bin/rm -f *.db";
ok(Genome::Model::Tools::Assembly::RemoveReads->execute(ace_file => $ace_file, contig => $contig, read_list => $read_list, out_file_name => $out_file_name), "RemoveReads executed successfully");

