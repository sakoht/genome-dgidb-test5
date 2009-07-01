#!/gsc/bin/perl

use strict;
use warnings;

use above 'Genome';
use Genome;

#use Test::More skip_all => 'test data not in place yet....';
#use Test::More tests => 5;

#BEGIN {
#    use_ok('Genome::Model::Tools::PooledBac::CreateBACProjectDirectories');
#}
use Genome::Model::Tools::PooledBac::CreateBACProjects;

my $project_dir = '/gscmnt/936/info/jschindl/pbtestout_for_tina';

Genome::Model::Tools::PooledBac::CreateBACProjects->execute(project_dir => $project_dir);
1;
