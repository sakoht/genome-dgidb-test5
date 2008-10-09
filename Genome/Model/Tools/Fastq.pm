package Genome::Model::Tools::Fastq;

use strict;
use warnings;

use Genome;
use Data::Dumper;

class Genome::Model::Tools::Fastq {
    is => 'Command',
    has => [
        fastq_file => {
            type => 'Text',
            is_optional => 0,
            doc => 'FASTA file. Quality file (if appropriate) will be named <fasta_file>\'.qual\'',
        },
    ],
};

sub help_brief {
    "tools for working with FASTQ files"
}

sub help_detail {
    "Tools to work with fastq format sequence/quality files";
}

sub create { 
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    $self->{_cwd} = Cwd::getcwd();
    $self->fasta_file( Cwd::abs_path( $self->fasta_file ) );
    my ($base, $directory) = File::Basename::fileparse( $self->fasta_file );
    chdir $directory
        or ( $self->error_message("Can't access directory ($directory): $!") and return );
    $self->{_fasta_base} = $base;

    return $self;
}

sub DESTROY {
    my $self = shift;

    chdir $self->_cwd;
    
    return 1;
}

sub _cwd {
    return shift->{_cwd};
}

sub _fasta_base {
    return shift->{_fasta_base};
}

sub qual_base {
    my $self = shift;

    return sprintf('%s.qual', $self->_fasta_base);
}

sub qual_file {
    my $self = shift;

    return sprintf('%s.qual', $self->fasta_file);
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

=item I<Synopsis>

=item I<Arguments>

=item I<Returns>

=back

=head1 See Also

=head1 Disclaimer

Copyright (C) 2005 - 2008 Washington University Genome Sequencing Center

This module is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=head1 Author(s)

B<Eddie Belter> I<ebelter@watson.wustl.edu>

=cut

#$HeadURL: /gscpan/perl_modules/trunk/Genome/Model/Tools/Fasta.pm $
#$Id: /gscpan/perl_modules/trunk/Genome/Model/Tools/Fasta.pm 39201 2008-09-29T18:26:47.471156Z ebelter  $

