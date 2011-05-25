#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';

use Test::More skip_all => "Does not play nice with the test harness";

my $ace_file = 'merge.ace';
my $contig = 'contig00012.0';
my $split_position = 150;
my $no_gui = 1;
my $path = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Assembly-MergeContigs/edit_dir';


my $out_file_name = 'split_out.ace';
chdir($path);
system "/bin/rm -f *.db";
ok(Genome::Model::Tools::Assembly::SplitContig->execute(ace_file => $ace_file, contig => $contig, split_position => $split_position, no_gui => $no_gui, out_file_name => $out_file_name), "SplitContig executed successfully");

