package Genome::Utility::IO::SeparatedValueWriter;

#:eclark 11/17/2009 Code review.

# use statements should be cleaned up, Genome is not used here.

use strict;
use warnings;

use Genome;

use Data::Compare 'Compare';
use Data::Dumper 'Dumper';

class Genome::Utility::IO::SeparatedValueWriter {
    is => 'Genome::Utility::IO::Writer', 
    has => [
    headers => {
        type => 'Array',
        doc => 'Headers to write and use in ordering value order.'
    },
    ],
    has_optional => [
    separator => {
        type => 'String',
        default => ',',
        doc => 'The value of the separator character.  Default: ","'
    },
    ],
};

sub create {
    my ($class, %params) = @_;

    my $headers = delete $params{headers}; # prevent UR from sorting our headers!
    unless ( $headers ) {
        $class->error_message("Headers are required to create.");
        return;
    }

    my $self = $class->SUPER::create(%params)
        or return;

    $self->headers($headers);
    $self->{_column_count} = scalar @$headers;
    $self->output->print( join($self->separator, @$headers)."\n" );
    
    return $self;
}

sub get_column_count {
    return $_[0]->{_column_count};
}

sub print { 
    my $self = shift;
    return $self->write_one(@_);
}

sub write_one {
    my ($self, $data) = @_;

    $self->_validate_data_to_write($data)
        or return;

    return $self->output->print(
        join(
            $self->separator,
            map { defined $_ ? $_ : '' } map { $data->{$_} } @{$self->headers}
        )."\n"
    );
}

sub _validate_data_to_write {
    my ($self, $data) = @_;

    unless ( $data ) {
        $self->error_message("No data sent to 'write_one'");
        return;
    }

    unless ( ref $data eq 'HASH' ) {
        $self->error_message("Need data as an hash ref to 'write_one'. Received:\n".Dumper($data));
        return;
    }

    unless ( %$data ) {
        $self->error_message("No data in data hash ref sent to 'write_one'");
        return;
    }
    
    unless ( Compare([ sort @{$self->headers} ], [ sort keys %$data ]) ) {
        $self->error_message("Headers in data do not match headers being written:\n".Dumper($data));
        return;
    }

    return 1;
}

1;

=pod

=head1 Name

Genome::Utility::IO::SeparatedValueWriter

=head1 Synopsis

A stream based reader that splits each line by the given separator.  If no headers are given, they will be derived from the first line of the io, being split by the separator.

=head1 Usage

 use Genome::Utility::IO::SeparatedValueReader;

 my $reader = Genome::Utility::IO::SeparatedValueReader->new (
    input => 'albums.txt', # REQ: file or object that can 'getline' and 'seek'
    headers => [qw/ title artist /], # OPT; headers for the file
    separator => '\t', # OPT; default is ','
    is_regex => 1, # OPT: 'set this flag if your separator is a regular expression, otherwise the literal characters of the separator will be used'
 );

 while ( my $album = $reader->next ) {
    print sprintf('%s by the famous %s', $album->{title}, $album->{artist}),"\n";
 }

=head1 Methods 

=head2 next

 my $ref = $reader->next;

=over

=item I<Synopsis>   Gets the next hashref form the input.

=item I<Params>     none

=item I<Returns>    scalar (hashref)

=back

=head2 all

 my @refs (or objects) = $reader->all;

=over

=item I<Synopsis>   Gets all the refs/objects form the input.  Calls _next in your class until it returns undefined or an error is encountered

=item I<Params>     none

=item I<Returns>    array (hashrefs or objects)

=back

=head2 getline

 $reader->getline
    or die;

=over

=item I<Synopsis>   Returns the next line form the input (not chomped)

=item I<Params>     none

=item I<Returns>    scalar (string)

=back

=head2 reset

 $reader->reset
    or die;

=over

=item I<Synopsis>   Resets (seek) the input to the beginning

=item I<Params>     none

=item I<Returns>    the result of the $self->input->seek (boolean)

=back

=head2 line_number

 my $line_number = $reader->line_number;

=over

=item I<Synopsis>   Gets the current line number (position) of the input

=item I<Params>     none

=item I<Returns>    line numeber (int)

=back

=head1 See Also

I<Genome::Utility::IO::SeparatedValueReader> (inherits from), I<UR>, I<Genome>

=head1 Disclaimer

Copyright (C) 2008 Washington University Genome Sequencing Center

This module is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=head1 Author(s)

Eddie Belter <ebelter@watson.wustl.edu>

=cut

#$HeadURL$
#$Id$
