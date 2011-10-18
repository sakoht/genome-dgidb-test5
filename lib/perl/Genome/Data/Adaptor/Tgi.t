#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use File::Temp;

use_ok('Genome::Data::Adaptor') or die;
use_ok('Genome::Data::Adaptor::Tgi') or die;

done_testing();


