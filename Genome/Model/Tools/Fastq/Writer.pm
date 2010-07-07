package Genome::Model::Tools::Fastq::Writer;

use strict;
use warnings;

use base 'Class::Accessor';

__PACKAGE__->mk_accessors(qw/ fastq_file _fh /);

use Data::Dumper 'Dumper';
require IO::File;

sub create {
    my ($class, %params) = @_;

    my $self = bless \%params, $class;

    my $fh = Genome::Utility::FileSystem->open_file_for_writing( $self->fastq_file );
    unless ( $fh ) {
        Carp::Confess("Can't open fastq file.");
    }
    $self->_fh($fh);
    
    return $self;
}

sub write {
    my ($self, $seq) = @_;

    $self->_fh->print(
        join(
            "\n",
            '@'.$seq->{id},#.( $seq->{desc} ? ' '.$seq->{desc} : '' ),
            $seq->{seq},
            '+',
            $seq->{qual},
        )."\n"
    );

    return 1;
}

sub flush {
    my $self = shift;

    return $self->_fh->flush;
}

1;

=pod

=head1 Name

ModuleTemplate

=head1 Synopsis

=head1 Usage

=head1 Methods

=head2 

=over

=item I<Synopsis

=item I<Arguments>

=item I<Returns>

=back

=head1 See Also

=head1 Disclaimer

Copyright (C) 2005 - 2009 Genome Center at Washington University in St. Louis

This module is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=head1 Author(s)

B<Eddie Belter> I<ebelter@genome.wustl.edu>

=cut

#$HeadURL$
#$Id$

