#! /gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

use Test::More;

use_ok('Genome::Model::Tools::Dacc::Ls') or die;

my $ls = Genome::Model::Tools::Dacc::Ls->create(
    dacc_directory => 'DACC_DIR',
);
ok($ls, 'create');
# do not test execute

done_testing();
exit;

=pod

=head1 Tests

=head1 Disclaimer

 Copyright (C) 2010 Washington University Genome Sequencing Center

 This script is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY
 or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
 License for more details.

=head1 Author(s)

 Eddie Belter <ebelter@watson.wustl.edu>

=cut

