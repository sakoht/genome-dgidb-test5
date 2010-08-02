#----------------------------------
# $Authors: dlarson bshore $
# $Date: 2008-09-16 16:33:54 -0500 (Tue, 16 Sep 2008) $
# $Revision: 38655 $
# $URL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/MG/MutationDiagram.pm $
#----------------------------------
package Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram;
#------------------------------------------------
our $VERSION = '1.0';
#------------------------------------------------
use strict;
use warnings;
use Carp;

use MPSampleData::Transcript;
use MG::Transform::Process::MutationCSV;
use MG::Validate::AminoAcidChange;
use Jalview::Feature::Domain;
use FileHandle;
use Genome;

use SVG;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::View;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Backbone;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Domain;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Mutation;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Legend;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::LayoutManager;
#------------------------------------------------
sub new {
    $DB::single = 1;
    my ($class, %arg) = @_;

    my $self = {
        _mutation_file => $arg{maf_file} || $arg{annotation} || '',
        _basename => $arg{basename} || './',
    };
    my @custom_domains =();
    if(defined($arg{custom_domains})) {
        my @domain_specification = split(',',$arg{custom_domains});
        
        while(@domain_specification) {
            my %domain = (type => "CUSTOM");
            @domain{qw(name start end)} = splice @domain_specification,0,3;
            push @custom_domains, \%domain;
        }
    }

    $self->{_custom_domains} = \@custom_domains;
        
    my @hugos = ();
    if (defined($arg{hugos})) {
        @hugos = split(',',$arg{hugos});
    }
    unless (scalar(@hugos)) {
        @hugos = qw( ALL );
    }
    $self->{_hugos} = \@hugos;
    bless($self, ref($class) || $class);
    if($arg{maf_file}) {
        $self->Maf();
    }
    elsif($arg{annotation}) {
        $self->Annotation;
    }
    else {
        die "No mutation file passed to $class";
    }
    $self->MakeDiagrams();
    return $self;
}

sub Annotation {
    #loads from annotation file format
    my $self = shift;
    my $annotation_file = $self->{_mutation_file};
    my $fh = new FileHandle;
    unless($fh->open("$annotation_file")) {
        die "Could not open annotation file $annotation_file";
    }
    print STDERR "Parsing annotation file...\n";
    my %data;
    my $graph_all = $self->{_hugos}->[0] eq 'ALL' ? 1 : 0;
    my %hugos;
    unless($graph_all) {
        %hugos = map {$_ => 1} @{$self->{_hugos}}; #convert array to hashset
    }
    
    while(my $line = $fh->getline) {
        chomp $line;
        next if $line =~/^chromosome/;
        my @fields = split /\t/, $line;
        my ($hugo,$transcript,$class,$aa_change) = @fields[6,7,13,15];
        if($graph_all || exists($hugos{$hugo})) {
            #add to the data hash for later graphing
            my ($residue1, $res_start, $residue2, $res_stop, $new_residue) = MG::Validate::AminoAcidChange::Check($aa_change);
            my $mutation = $aa_change;
            $mutation =~ s/p\.//g;
            unless(defined($transcript) && $transcript !~ /^\s*$/) {
                next;
            }

            my $dom = new Jalview::Feature::Domain();
            $dom->query_domain_features('-transcript-list' => [ $transcript ]);
            my (@features) = @{ $dom->get_features(); };
            my @domains;
            if($self->{_custom_domains}->[0]) {
                push @domains, @{$self->{_custom_domains}};
            }
            my $protein_length = get_protein_length($transcript);
            foreach my $feature (@features) {
                my ($name) = $feature->get_tag_values("domain");
                my ($type, @domain_names) = split('_',$name);
                my $domain_name = join('_',@domain_names);
                push @domains, {
                    name => $domain_name,
                    type => $type,
                    start => $feature->start,
                    end => $feature->end
                };
            }
            $data{$hugo}{$transcript}{length} = $protein_length;
            push @{$data{$hugo}{$transcript}{domains}}, @domains;

            if (defined($res_start)) {
                unless (exists($data{$hugo}{$transcript}{mutations}{$mutation})) {
                    $data{$hugo}{$transcript}{mutations}{$mutation} = 
                    {
                        res_start => $res_start,
                        class => $class,
                    };
                }
                $data{$hugo}{$transcript}{mutations}{$mutation}{frequency} += 1;
            }
        }
    }
    $self->{_data} = \%data;
}


sub Maf {
    my ($self) = @_;
    my %maf_args = (
        all => 1,
        no_process => 1,
        version => 3, #TODO change to parameter
    );
    my $parser = MG::Transform::Process::MutationCSV->new;
    my $fh = new FileHandle;
    my $mutation_file = $self->{_mutation_file};
    unless ($fh->open (qq{$mutation_file})) {
        die "Could not open csv file '$mutation_file' for reading $$";
    }
    print STDERR "Parsing maf file...\n";
    my $mutations = $parser->Parse($fh,$mutation_file,%maf_args);
    $fh->close;

    my $hugo;
    my $transcript;
    if ($self->{_hugos}->[0] eq 'ALL') {
        my @hugos = (keys %{$mutations});
        $self->{_hugos} = \@hugos;
    }
    foreach $hugo (@{$self->{_hugos}}) {
        if(exists($mutations->{$hugo})) {
            foreach my $sample (keys %{$mutations->{$hugo}}) {
                foreach my $line_num (keys %{$mutations->{$hugo}{$sample}}) {
                    my $aa_change = $mutations->{$hugo}{$sample}{$line_num}{PROT_STRING};
#               my $aa_change = $mutations->{$hugo}{$sample}{$line_num}{AA_CHANGE};
                    unless (defined($aa_change)) {
                        next;
                    }
                    my $type = $mutations->{$hugo}{$sample}{$line_num}{VARIANT_TYPE};
                    my $class = $mutations->{$hugo}{$sample}{$line_num}{VARIANT_CLASSIFICATION};
                    $class =~ s/_mutation$//i;
                    my ($residue1, $res_start, $residue2, $res_stop, $new_residue) = MG::Validate::AminoAcidChange::Check($aa_change);
                    my $mutation = $aa_change;
                    $mutation =~ s/p\.//g;

                    $transcript = $mutations->{$hugo}{$sample}{$line_num}{TRANSCRIPT};
                    unless (defined($transcript) && $transcript !~ /^\s*$/) {
                        next;
                    }
                    my $dom = new Jalview::Feature::Domain();
                    $dom->query_domain_features('-transcript-list' => [ $transcript ]);
                    my (@features) = @{ $dom->get_features(); };
                    my @domains;
                    my $protein_length = get_protein_length($transcript);
                    foreach my $feature (@features) {
                        my ($name) = $feature->get_tag_values("domain");
                        my ($type, @domain_names) = split('_',$name);
                        my $domain_name = join('_',@domain_names);
                        push @domains, {
                            name => $domain_name,
                            type => $type,
                            start => $feature->start,
                            end => $feature->end
                        };
                    }
                    $self->{_data}{$hugo}{$transcript}{length} = $protein_length;
                    push @{$self->{_data}{$hugo}{$transcript}{domains}}, @domains;
                    if (defined($res_start)) {
                        unless (exists($self->{_data}{$hugo}{$transcript}{mutations}{$mutation})) {
                            $self->{_data}{$hugo}{$transcript}{mutations}{$mutation} = 
                            {
                                res_start => $res_start,
                                #                      maf => $mutations->{$hugo}{$sample}{$line_num},
                                type => $type,
                                class => $class
                            };
                        }
                        $self->{_data}{$hugo}{$transcript}{mutations}{$mutation}{frequency} += 1;
                    }
                }
            }
        }
    }

    return $self;
}

sub get_protein_length{
    #This needs to reference our annotation database to yield the best results...
    #Going to hardcode this here. In the future we will need to have annotation options exposed...
    
    my ($tr)=MPSampleData::Transcript->search("transcript_name"=>shift);
    my ($protein)=MPSampleData::Protein->search("transcript_id"=>$tr->transcript_id);
    return 0 unless($protein);
    return length($protein->amino_acid_seq);
} 

sub Data {
    my ($self) = @_;
    return $self->{_data};
}

sub MakeDiagrams {
    my ($self) = @_;
    my $data = $self->{_data};
    my $basename = $self->{_basename};
    foreach my $hugo (keys %{$data}) {
        foreach my $transcript (keys %{$data->{$hugo}}) {
            my $svg_file = $basename . $hugo . '_' . $transcript . '.svg';
            my $svg_fh = new FileHandle;
            unless ($svg_fh->open (">$svg_file")) {
                die "Could not create file '$svg_file' for writing $$";
            }
            $self->Draw($svg_fh,
                $hugo, $transcript,
                $self->{_data}{$hugo}{$transcript}{length},
                $self->{_data}{$hugo}{$transcript}{domains},
                $self->{_data}{$hugo}{$transcript}{mutations}
            );
            $svg_fh->close();
        }
    }
    return $self;
}

sub Draw {
    my ($self, $svg_fh, $hugo, $transcript, $length, $domains, $mutations) = @_;

    my $document = Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::View->new(width=>'800',height=>'600',
        'viewport' => {x => 0, y => 0,
            width => 800,
            height => 600},
        left_margin => 50,
        right_margin => 50,);
    my $svg = $document->svg;

    my $backbone = Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Backbone->new(parent => $document,
        gene => $hugo,
        protein_length => $length,
        backbone_height
        =>
        50,
        style => {fill => 'none', stroke => 'black'},
        $document->content_view);
    $backbone->draw;

    my @colors = qw( red green orange blue cyan yellow violet brown magenta aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blueviolet burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod greenyellow honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightsteelblue lightyellow lime limegreen linen maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise wheat whitesmoke yellowgreen );
    my $color = 0;
    my %domains;
    my %domains_location;
    my %domain_legend;
    foreach my $domain (@{$domains}) {
        if ($domain->{type} eq 'superfamily') {
            next;
        }
        my $domain_color;
        if (exists($domain_legend{$domain->{name}})) {
            $domain_color = $domain_legend{$domain->{name}};
        } else {
            $domain_color = $colors[$color++];
            $domain_legend{$domain->{name}} = $domain_color;
        }
        if (exists($domains_location{$domain->{name}}{$domain->{start} . $domain->{end}})) {
            next;
        }
        $domains_location{$domain->{name}}{$domain->{start} . $domain->{end}} += 1;
        $domains{$domain->{name}} += 1;
        my $subid = '';
        if ($domains{$domain->{name}} > 1) {
            $subid = '_subid' . $domains{$domain->{name}};
        }
        my $test_domain = Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Domain->new(backbone => $backbone,
            start_aa => $domain->{start},
            stop_aa => $domain->{end},
            id => 'domain_' . $domain->{name} . $subid,
            text => $domain->{name},
            style => { fill => $domain_color,
                stroke => 'black'});
        $color++;
        $test_domain->draw;
    }
    my $domain_legend =
    Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Legend->new(backbone => $backbone,
        id => 'domain_legend',
        x => $length / 2,
        values => \%domain_legend,
        object => 'rectangle',
        style => {stroke => 'black', fill => 'none'});
    $domain_legend->draw;

    my @mutation_objects;
    my %mutation_class_colors = (
        'frame_shift_del' => 'blue',
        'frame_shift_ins' => 'orange',
        'in_frame_del' => 'green',
        'missense' => 'cyan',
        'nonsense' => 'yellow',
        'splice_site_del' => 'violet',
        'splice_site_indel' => 'brown',
        'splice_site_snp' => 'purple',
        'other' => 'red'
    );
    my %mutation_legend;
    my $max_frequency = 0;
    my $max_freq_mut;
    foreach my $mutation (keys %{ $mutations}) {
        $mutations->{$mutation}{res_start} ||= 0;
        my $mutation_color = $mutation_class_colors{lc($mutations->{$mutation}{class})};
        $mutation_color ||= $mutation_class_colors{'other'};
        $mutation_legend{$mutations->{$mutation}{class}} = $mutation_color;
        my $mutation_element =
        Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Mutation->new(backbone => $backbone,
            id => $mutation,
            start_aa => $mutations->{$mutation}{res_start},
            text => $mutation,
            frequency => $mutations->{$mutation}{frequency},
            color => $mutation_color,
            style => {stroke => 'black', fill => 'none'});


        #jitter labels as a test
        push @mutation_objects, $mutation_element;
        if($mutations->{$mutation}{frequency} > $max_frequency) {
            $max_frequency = $mutations->{$mutation}{frequency};
            $max_freq_mut = $mutation_element;
        }
    }
    map {$_->vertically_align_to($max_freq_mut)} @mutation_objects;
    my $mutation_legend =
    Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Legend->new(backbone => $backbone,
        id => 'mutation_legend',
        x => 0,
        values => \%mutation_legend,
        object => 'circle',
        style => {stroke => 'black', fill => 'none'});
    $mutation_legend->draw;


    my $layout_manager = Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::LayoutManager->new(iterations => 1000,
        max_distance => 13, spring_constant => 6, spring_force => 1, attractive_weight => 5 );
    $layout_manager->layout(@mutation_objects);

    map {$_->draw;} (@mutation_objects);

    # now render the SVG object, implicitly use svg namespace
    print $svg_fh $svg->xmlify;
}
