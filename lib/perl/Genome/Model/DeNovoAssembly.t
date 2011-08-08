#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';

use Test::More;

use_ok('Genome::Model::DeNovoAssembly');

my %tissue_descs_and_name_parts = (
    '20l_p' => undef,
    'u87' => undef,
    'zo3_G_DNA_Attached gingivae' => 'Attached Gingivae',
    'lung, nos' => 'Lung Nos',
    'mock community' => 'Mock Community',
);
for my $tissue_desc ( keys %tissue_descs_and_name_parts ) {
    my $name_part = Genome::Model::DeNovoAssembly->_get_name_part_from_tissue_desc($tissue_desc);
    is($name_part, $tissue_descs_and_name_parts{$tissue_desc}, 'tissue desc converted to name part');
}

done_testing();
exit;

