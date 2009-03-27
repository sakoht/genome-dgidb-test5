package Genome::Utility::MetagenomicClassifier::SequenceClassification;

use strict;
use warnings;

use Carp 'confess';
use Data::Dumper 'Dumper';

sub new {
    my ($class, %params) = @_;

    my $self =  bless \%params, $class;

    for my $req (qw/ name classifier taxon /) {
        _fatal_message("Required parameter ($req) not found.") unless $params{$req};
    }

    $self->{complemented} = 0 unless $self->{complemented};

   
    return $self;
}

sub _fatal_message {
    my ($msg) = @_;

    confess __PACKAGE__." ERROR: $msg\n";
}
 
#< NAME >#
sub get_name {
    return $_[0]->{name};
}

#< COMPLEMENTED >#
sub get_complemented { 
    return $_[0]->{complemented};
}

sub is_complemented { 
    return $_[0]->{complemented};
}

#< CLASSIFIER TYPE >#
sub get_classifier {
    return $_[0]->{classifier};
}

#< TAXON >#
sub _set_ranks_and_taxa {
    my $self = shift;

    return 1 if $self->{_taxa};
    
    my $i = 0;
    my (%ranks, @taxa);

    my $taxon = $self->get_taxon;
    do { 
        push @taxa, $taxon;
        $ranks{ lc($taxon->rank) } = $i++;
        ($taxon) = $taxon->get_Descendents;
    } until not defined $taxon;

    unless ( @taxa ) { 
        _fatal_message("No descendant taxa found in taxon: ".$self->get_taxon->id);
        return;
    }

    $self->{_taxa} = \@taxa;
    $self->{_ranks} = \%ranks;

    return 1;
}

sub get_taxon {
    return $_[0]->{taxon};
}

sub get_taxon_at_depth {
    my $self = shift;
    my $depth = shift;

    my $current_taxon = $self->get_taxon;
    my $current_depth = 0;
    while ($current_depth < $depth) {
        ($current_taxon) = $current_taxon->get_Descendents;
        $current_depth ++;
        unless ($current_taxon) {
            return undef;
        }
    }
    return $current_taxon;
}

sub to_string {
    my $self = shift;
    my @taxa = $self->get_taxa;
    my $string = "";

    my $taxon = shift @taxa;
    $string .= $taxon->id;
    while ($taxon = shift @taxa) {
        $string .= ":";
        $string .= $taxon->id;
    }

    return $string;
}

sub get_ranks {
    my $self = shift;

    $self->_set_ranks_and_taxa
        or return;
 
    my $ranks = $self->{_ranks};
    
    return map { $ranks->{$_} } sort keys %$ranks;
}

sub get_taxa {
    my $self = shift;

    $self->_set_ranks_and_taxa
        or return;
 
    return @{$self->{_taxa}};
}

sub taxa_count { 
    return scalar( $_[0]->get_taxa );
}

sub _get_taxon_for_rank {
    my ($self, $rank) = @_;
    
    $rank = lc $rank;
    my @taxa = $self->get_taxa;
    return $taxa[ $self->{_ranks}->{$rank} ];
}

sub _get_taxon_name_for_rank {
    my ($self, $rank) = @_;

    my $taxon = $self->_get_taxon_for_rank($rank)
        or return 'none';

    return $taxon->id;
}

sub _get_taxon_name_and_confidence {
    my ($self, $rank) = @_;

    my $taxon = $self->_get_taxon_for_rank($rank)
        or return;

    return ($taxon->id, ($taxon->get_tag_values('confidence'))[0]);
}

sub get_root_taxon {
    return $_[0]->_get_taxon_for_rank('root');
}

sub get_root {
    return $_[0]->_get_taxon_name_for_rank('root');
}

sub get_domain_taxon {
    return $_[0]->_get_taxon_for_rank('domain');
}

sub get_domain {
    return $_[0]->_get_taxon_name_for_rank('domain');
}

sub get_domain_confidence {
    my $self = shift;
    my $domain_taxon = $self->get_domain_taxon;
    unless ($domain_taxon) {
        return;
    }
    my ($confidence) = $domain_taxon->get_tag_values('confidence');
    return $confidence;
}

sub get_domain_name_and_confidence {
    return $_[0]->_get_taxon_name_and_confidence('domain');
}

sub get_kingdom_taxon {
    return $_[0]->_get_taxon_for_rank('kingdom');
}

sub get_kingdom {
    return $_[0]->_get_taxon_name_for_rank('kingdom');
}

sub get_kingdom_confidence {
    my $self = shift;
    my $kingdom_taxon = $self->get_kingdom_taxon;
    unless ($kingdom_taxon) {
        return;
    }
    my ($confidence) = $kingdom_taxon->get_tag_values('confidence');
    return $confidence;
}

sub get_phylum_taxon {
    return $_[0]->_get_taxon_for_rank('phylum');
}

sub get_phylum {
    return $_[0]->_get_taxon_name_for_rank('phylum');
}

sub get_phylum_confidence {
    my $self = shift;
    my $phylum_taxon = $self->get_phylum_taxon;
    unless ($phylum_taxon) {
        return;
    }
    my ($confidence) = $phylum_taxon->get_tag_values('confidence');
    return $confidence;
}

sub get_class_taxon {
    return $_[0]->_get_taxon_for_rank('class');
}

sub get_class {
    return $_[0]->_get_taxon_name_for_rank('class');
}

sub get_class_confidence {
    my $self = shift;
    my $class_taxon = $self->get_class_taxon;
    unless ($class_taxon) {
        return;
    }
    my ($confidence) = $class_taxon->get_tag_values('confidence');
    return $confidence;
}

sub get_order_taxon {
    return $_[0]->_get_taxon_for_rank('order');
}

sub get_order {
    return $_[0]->_get_taxon_name_for_rank('order');
}

sub get_order_confidence {
    my $self = shift;
    my $order_taxon = $self->get_order_taxon;
    unless ($order_taxon) {
        return;
    }
    my ($confidence) = $order_taxon->get_tag_values('confidence');
    return $confidence;
}

sub get_family_taxon {
    return $_[0]->_get_taxon_for_rank('family');
}

sub get_family {
    return $_[0]->_get_taxon_name_for_rank('family');
}

sub get_family_confidence {
    my $self = shift;
    my $family_taxon = $self->get_family_taxon;
    unless ($family_taxon) {
        return;
    }
    my ($confidence) = $family_taxon->get_tag_values('confidence');
    return $confidence;
}

sub get_genus_taxon {
    return $_[0]->_get_taxon_for_rank('genus');
}

sub get_genus {
    return $_[0]->_get_taxon_name_for_rank('genus');
}

sub get_genus_confidence {
    my $self = shift;
    my $genus_taxon = $self->get_genus_taxon;
    unless ($genus_taxon) {
        return;
    }
    my ($confidence) = $genus_taxon->get_tag_values('confidence');
    return $confidence;
}

sub get_genus_name_and_confidence {
    return $_[0]->_get_taxon_name_and_confidence('genus');
}

sub get_species_taxon {
    return $_[0]->_get_taxon_for_rank('species');
}

sub get_species {
    return $_[0]->_get_taxon_name_for_rank('species');
}

sub get_species_confidence {
    my $self = shift;
    my $species_taxon = $self->get_species_taxon;
    unless ($species_taxon) {
        return;
    }
    my ($confidence) = $species_taxon->get_tag_values('confidence');
    return $confidence;
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

#$HeadURL$
#$Id$

