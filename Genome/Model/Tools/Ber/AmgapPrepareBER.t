#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";
use File::Remove qw/ remove /;

use Test::More tests => 3;

BEGIN {
    use_ok('Genome::Model::Tools::Ber::AmgapPrepareBER');
}

unless( -d "/tmp/disk/")
{
    mkdir("/tmp/disk");
}

unless( -l "/tmp/disk/analysis")
{
    symlink("/gsc/var/cache/testsuite/data/Genome-Model-Tools-Hgmi/analysis",
            "/tmp/disk/analysis");
}


my $tool_db = Genome::Model::Tools::Ber::AmgapPrepareBER->create(
                    'locus_tag'       => "PNI0002DFT",
		    'sequence_set_id' => "221",
		    'phase'           => "5",
		);
isa_ok($tool_db,'Genome::Model::Tools::Ber::AmgapPrepareBER');


ok($tool_db->execute,'execute amgapprepareber');



