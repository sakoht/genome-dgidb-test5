package Genome::Utility::IO::BedReader;

use strict;
use warnings;

use Genome;

my @DEFAULT_HEADERS = qw/chr start end name score strand/;

class Genome::Utility::IO::BedReader {
    is => ['Genome::Utility::IO::SeparatedValueReader'],
    has => [
        ignore_lines_starting_with => {
            default_value => 'track',
        },
        separator => {
            default_value => "\t",
        },
    ],
};

sub default_headers {
    return \@DEFAULT_HEADERS;
}

sub create {
    my $class = shift;
    my %params = @_;

    my $headers = delete $params{headers};
    unless ($headers) {
        $headers = $class->default_headers;
    }
    $params{headers} = $headers;
    my $self = $class->SUPER::create(%params)
        or return;
    return $self;
}


1;
