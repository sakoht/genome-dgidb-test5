#!/gsc/bin/perl

use strict;
use warnings;

use lib '/gscuser/mjohnson/bioperl-svn/bioperl-live';
use lib '/gscuser/mjohnson/bioperl-svn/bioperl-run';

use above 'Workflow';
use Data::Dumper;
use PAP;

my $i = Workflow::Store::Db::Operation::Instance->get(337);

$i->treeview_debug;

