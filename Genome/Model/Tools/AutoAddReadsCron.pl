#!/gsc/bin/perl

use strict;
use warnings;

use above 'Genome';
#use lib '/gsc/scripts/lib/perl';
#use lib 'gscuser/jeldred/svn/gscpan/perl_modules/trunk/Genome';

#$ENV{'PERL5LIB'} = '/gsc/scripts/lib/perl/:' . $ENV{'PERL5LIB'};

Genome::Model::Tools::AutoAddReads->execute();

1;