package Genome::Info::UCSCConservation;

use strict;
use warnings;
use Genome;

my %ucsc_conservation_directories =
(
   36 => "/gscmnt/sata849/info/v36_ucsc_conservation",
   37 => "/gscmnt/sata849/info/v37_ucsc_conservation",

);

sub ucsc_conservation_directories{
    return %ucsc_conservation_directories;
}

1;
