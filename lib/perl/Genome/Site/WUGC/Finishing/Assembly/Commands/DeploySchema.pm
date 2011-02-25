package Genome::Site::WUGC::Finishing::Assembly::Commands::DeploySchema;

use strict;
use warnings;

use base 'Genome::Site::WUGC::Finishing::Assembly::Commands::Base';

use Data::Dumper;

sub execute
{
    my $self = shift;

    my $factory = $self->_factory;

    return $factory->txn_do( sub{ $factory->deploy; });
}

1;

=pod

=head1 Name

Genome::Site::WUGC::Finishing::Assembly::Commands::DeploySchema

=head1 Synopsis

=head1 Usage

=head1 Methods

=head1 See Also

=head1 Disclaimer

Copyright (C) 2007 Washington University Genome Sequencing Center

This module is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=head1 Author(s)

B<Eddie Belter> I<ebelter@watson.wustl.edu>

=cut

#$HeadURL$
#$Id$

