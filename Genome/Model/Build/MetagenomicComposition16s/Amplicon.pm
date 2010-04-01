package Genome::Model::Build::MetagenomicComposition16s::Amplicon;

use strict;
use warnings;

use Genome;

use Carp 'confess';
use Data::Dumper 'Dumper';
require Storable;

class Genome::Model::Build::MetagenomicComposition16s::Amplicon {
    is => 'UR::Object',
    has => [
        name => {
            is => 'Text',
            doc => 'Name of amplicon.',
        },
        reads => {
            is => 'ARRAY',
            doc => 'Reads for the amplicon.',
        },
        classification_file => {
            is => 'Text',
            doc => 'Classification storable file.',
        },
    ],
    has_optional => [
        assembled_reads => {
            is => 'ARRAY',
            doc => 'Reads that were assembled.',
        },
        bioseq => {
            is => 'Bio::Seq',
            doc => 'Amplicon\'s processed Bio::Seq object.  Not oriented.',
        },
    ],
};

#< UR >#
sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_)
        or return;

    for my $attr (qw/ name reads classification_file /) {
        next if $self->$attr;
        $self->error_message("Attribute ($attr) is required to create");
        $self->delete;
        return;
    }

    return $self;
}

#< Oriented Bioseq >#
sub oriented_bioseq {
    my $self = shift;

    my $bioseq = $self->bioseq
        or return; # ok

    my $classification = $self->classification
        or return; # ok

    if ( $classification->is_complemented ) {
        eval { $bioseq = $bioseq->revcom; };
        unless ( $bioseq ) { # bad
            die "Can't reverse complement biobioseq for amplicon (".$self->name."): $!";
        }
    }

    return $bioseq;
}

#< Read Counts >#
sub read_count {
    return scalar(@{$_[0]->reads});
}

sub assembled_read_count {
    my $self = shift;
    return $self->assembled_reads
    ? scalar(@{$self->assembled_reads})
    : undef;
}

#< Classification >#
sub classification {
    my ($self, $classification) = @_;

    if ( $classification ) { #save
        my $classification_file = $self->classification_file;
        unlink $classification_file if -e $classification_file;
        eval {
            Storable::store($classification, $classification_file);
        };
        if ( $@ ) {
            $self->error_message("Can't store amplicon's (".$self->name.") classification to file ($classification_file)");
            return;
        }

        $self->{classification} = $classification;
        return $self->{classification};
    }

    return $self->{classification} if $self->{classification};

    # load
    my $classification_file = $self->classification_file;
    return unless -s $classification_file; # ok
    
    eval {
        $classification = Storable::retrieve($classification_file);
    };
    
    unless ( $classification ) {
        $self->error_message("Can't retrieve amplicon's (".$self->name.") classification from file ($classification_file) for ".$self->description);
        die;
    }

    $self->{classification} = $classification;
    return $self->{classification};
}

1;

=pod

=head1 Disclaimer

Copyright (C) 2010 Genome Center at Washington University in St. Louis

This module is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY or the implied
 warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

=head1 Author(s)

B<Eddie Belter> I<ebelter@genome.wustl.edu>

=cut

#$HeadURL$
#$Id$
