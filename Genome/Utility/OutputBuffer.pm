package Genome::Utility::OutputBuffer;

use strict;
use warnings;
use Data::Dumper;

use IO::File;

my $linelength = 60;

sub new{
    my $class = shift;
    my $file = shift;
    my $io = IO::File->new("> ".$file);
    die "can't create io from $file" unless $io;
    my $self = bless({_io => $io, current_line_avail => $linelength},$class);
    return $self;
}

sub print_header{
    my ($self, $header) = @_;
    #don't print leading newline if we're at the top of the file
    $self->{_io}->print("\n") unless $self->{current_line_avail} == $linelength;
    $self->{_io}->print("$header\n") or $self->fatal_msg("can't write header $header");
    $self->{current_line_avail} = $linelength;
    return 1;
}

sub print{
    my $self = shift;
    my $avail = $self->{current_line_avail};
    my $io = $self->{_io};
    while ($_ = shift @_) {
        next unless $_;
        my $next = substr($_,0,$avail);
        $io->print($next);
        $avail -= length($next);
        if ($avail == 0) {
            $io->print("\n");
            $avail = $linelength;
        }                    
        $_ = substr($_,length($next));
        redo if length($_);        
    }
    $self->{current_line_avail}=$avail;
    return 1;
}

sub close{
    my $self = shift;
    my $io = $self->{_io};
    $io->print("\n");
    $io->close();
}

=pod

=head1 OutputBuffer
Simple output writer for taking arbitrary length input and writing output of max line length(60)

my $ob = Genome::Utility::OutputBuffer->new(<file>);

$ob->print_header(">Sequence_1");

while{
    ...
    (create $seq of arbitrary length
    ...
    $ob->print("$seq);
}

=head2 Subs

=head3 print_header($string)
prints $string followed by a newline to the file

=head3 print($string)
prints $string to the file, automatically inserting a newline when the max line_length(60) is reached

=cut

1;
