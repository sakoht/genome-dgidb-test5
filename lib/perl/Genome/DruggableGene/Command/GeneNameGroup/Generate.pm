package Genome::DruggableGene::Command::GeneNameGroup::Generate;

use strict;
use warnings;
use Genome;
use List::MoreUtils qw/ uniq /;

class Genome::DruggableGene::Command::GeneNameGroup::Generate{
    is => 'Genome::Command::Base',
    doc => 'Generate a ton of groups to bundle genes with similar alternate names',
};

sub help_brief { 'Generate a ton of groups to bundle genes with similar alternate names' }

sub help_synopsis { help_brief() }

sub help_detail { help_brief() }

sub load {
    my $self = shift;

    print "Preloading all genes\n";
    Genome::DruggableGene::GeneNameReport->get;#Preload

    print "Loading alternate names and creating hash\n";
    my %alt_to_entrez;
    my %alt_to_other;

    for (Genome::DruggableGene::GeneAlternateNameReport->get) { #operate on all alternate names
        my $alt = $_->alternate_name;
        print "Skipping $alt\n" and next if $alt =~ /^.$/;    #ignore single character names
        print "Skipping $alt\n" and next if $alt =~ /^\d\d$/; #ignore 2 digit names

        #Save genes with the same alternate name in an array in a hash with key being the alt-name
        if($_->nomenclature eq 'entrez_gene_symbol'){
            push @{ $alt_to_entrez{$alt} }, $_;
        } else {
            push @{ $alt_to_other{$alt} }, $_;
        }
    }

    return \%alt_to_entrez, \%alt_to_other;
}

sub create_groups {
    my $self = shift;
    my $alt_to_entrez = shift;
    my $progress_counter = 0;

    print "Putting " . scalar(keys(%{$alt_to_entrez})) . " entrez gene symbol hugo names into groups\n";
    for my $alt (keys %{$alt_to_entrez}) {
        $progress_counter++;
        my @genes = map{$_->gene} @{$alt_to_entrez->{$alt}};

        my $group = Genome::DruggableGene::GeneNameGroup->get(name => $alt);
        if($group){ #hugo name group already exists
            for my $gene (@genes){#make sure each gene is already in this group
                Genome::DruggableGene::GeneNameGroupBridge->create(
                    gene_id => $gene->id,
                    gene_id => $group->id
                ) if not Genome::DruggableGene::GeneNameGroupBridge->get(gene_id => $gene->id);
            }
        }else{
            $group = Genome::DruggableGene::GeneNameGroup->create(name => $alt);
            Genome::DruggableGene::GeneNameGroupBridge->create(gene_id => $_->id, gene_id => $group->id) for @genes;
        }
        print "$progress_counter : created new group for $alt\n" if rand() < .001;
    }

    print "\n****\nFinished $progress_counter.\n****\n\n";
}

sub add_members {
    my $self = shift;
    my $alt_to_other = shift;
    my $progress_counter = 0;
    print "Now processing all " . scalar @{[Genome::DruggableGene::GeneNameReport->get]} . " to add members to groups\n";

    for my $gene (Genome::DruggableGene::GeneNameReport->get){
        $progress_counter++;
        next if Genome::DruggableGene::GeneNameGroupBridge->get(gene_id => $gene->id); #if already in a group


        my %indirect_groups;#groups found through alternate names
        my %direct_groups;#groups found through hugo name
        my $gene_name = $gene->name;

        $direct_groups{$gene_name}++ if Genome::DruggableGene::GeneNameGroup->get(name=>$gene_name); #go genes for instance have hugo names

        for my $alt($gene->alternate_names){
            $direct_groups{$alt}++ if Genome::DruggableGene::GeneNameGroup->get(name=>$alt);

            my @alt_genes = map{$_->gene} @{$alt_to_other->{$alt}};
            for my $alt_gene (@alt_genes){
                #Get the group if it exists and add it to our list of indirectly found groups
                my $bridge = Genome::DruggableGene::GeneNameGroupBridge->get(gene_id => $alt_gene->id);
                $indirect_groups{$bridge->gene->name}++ if $bridge;
            }
        }

        #If we found exactly one group, add this gene to it
        if(scalar keys %direct_groups == 1){
            my ($group_name) = keys %direct_groups;
            my $group_id = Genome::DruggableGene::GeneNameGroup->get(name=>$group_name)->id;
            Genome::DruggableGene::GeneNameGroupBridge->create(gene_id => $gene->id, gene_id => $group_id);
            print "$progress_counter : added $gene_name to $group_name directly\n" if rand() < .001;
            next;
        }

        if(scalar keys %direct_groups == 0 and scalar keys %indirect_groups == 1){
            my ($group_name) = keys %indirect_groups;
            my $group_id = Genome::DruggableGene::GeneNameGroup->get(name=>$group_name)->id;
            Genome::DruggableGene::GeneNameGroupBridge->create(gene_id => $gene->id, gene_id => $group_id);
            print "$progress_counter : added $gene_name to $group_name indirectly\n" if rand() < .001;
            next;
        }
        print "$progress_counter : failed to add $gene_name to any group. Direct: " .
        join(' ',keys %direct_groups) . "   Indirect: " . join(' ',keys %indirect_groups) . "\n" if rand() < .001;
    }
}

sub execute {
    my $self = shift;

    my ($alt_to_entrez, $alt_to_other) = $self->load();
    $self->create_groups($alt_to_entrez);#Group names are only hugo names
    $self->add_members($alt_to_other);

    return 1;
}
1;
