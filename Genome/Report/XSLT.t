#!/usr/bin/env perl

use strict;
use warnings;

use above "Genome";

use Genome::Report::Test;

Genome::Report::XSLT::Test->runtests;

exit;

#$HeadURL$
#$Id$
