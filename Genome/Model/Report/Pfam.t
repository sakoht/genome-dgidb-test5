#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;
use above "Genome";

BEGIN {
    use_ok("Genome::Model::Report::Pfam");
}


