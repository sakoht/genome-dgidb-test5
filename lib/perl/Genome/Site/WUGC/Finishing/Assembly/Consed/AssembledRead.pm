package Genome::Site::WUGC::Finishing::Assembly::Consed::AssembledRead;

use strict;
use warnings;

use base 'Finfo::Accessor';

use Data::Dumper;

__PACKAGE__->mk_accessors(qw/ ace_source /);

sub phd_source
{
    my $self = shift;

    return $self->{_phd_source} if $self->{_phd_source};

    return $self->{_phd_source} = $self->{phd_source}->();
}

1;

=pod

=head1 Name

Genome::Site::WUGC::Finishing::Assembly::Ace::AssembledRead

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

