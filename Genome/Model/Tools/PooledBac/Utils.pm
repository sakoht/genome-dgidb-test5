package Genome::Model::Tools::PooledBac::Utils;

use strict;
use warnings;
use Genome;
use Genome::Utility::FileSystem;
use List::Util qw(max min);

class Genome::Model::Tools::PooledBac::Utils {
    is => 'UR::Object',
    has => [ ]
};

sub create
{
    my $class = shift;
    my $self = $class->SUPER::create(@_);

    return $self;
}

sub write_fasta_from_contig_names
{
    my ($self, $ao, $fasta_fn, $qual_fn, $po, $contig_names) = @_;

    my $fasta_fh = IO::File->new(">$fasta_fn");
    $self->error_message("File $fasta_fn failed to open for writing.") and die unless defined $fasta_fh;
    my $qual_fh = IO::File->new(">$qual_fn");
    $self->error_message("File $qual_fn failed to open for writing.") and die unless defined $qual_fh;     
    foreach my $contig_name (@{$contig_names})
    {
        $self->write_reads_to_fasta($ao, $fasta_fh, $qual_fh, $po, $contig_name);
    }
    $fasta_fh->close;
    $qual_fh->close;
}



sub write_reads_to_fasta
{
    my ($self,$ao, $fasta_fh, $qual_fh, $po, $contig_name) = @_;
    my %phd_names = $self->get_phd_names($ao,$contig_name);
    
    foreach my $read_name (keys %phd_names)
    {
        my $phd = $po->get_phd($phd_names{$read_name});
        $fasta_fh->print(">$read_name\n");
        $qual_fh->print(">$read_name\n");
        $fasta_fh->print($phd->unpadded_base_string,"\n");
        $qual_fh->print(join ' ',@{$phd->unpadded_base_quality}, "\n");    
    }
}

sub get_phd_names
{
    my ($self,$ao, $contig_name) = @_;   
   
    my $co = $ao->get_contig($contig_name);
    my $reads = $co->reads;
    #print $co->name,"\n";
    my %phd_names;
    foreach (values %{$reads})
    {
        $phd_names{$_->name}= $_->phd_file;
    }
    return %phd_names;
}

sub comp_hits
{
    return $a->{HSP_LENGTH} <=> $b->{HSP_LENGTH} if($a->{HSP_LENGTH} != $b->{HSP_LENGTH});
    return ($a->{IDENTICAL}/$a->{HSP_LENGTH} )<=> ($b->{IDENTICAL}/$b->{HSP_LENGTH});
}

sub comp_hit_lists
{
    my $c = $a->[0];
    my $d = $b->[0];
    return $c->{HSP_LENGTH} <=> $d->{HSP_LENGTH} if($c->{HSP_LENGTH} != $d->{HSP_LENGTH});
    return ($c->{IDENTICAL}/$c->{HSP_LENGTH} )<=> ($d->{IDENTICAL}/$d->{HSP_LENGTH});
    
}

sub get_matching_contigs_list
{
    my ($self, $out) = @_;
    #top sorted list of all contigs meeting cutoffs
    #sort by length, then percent identity
    #print contig name, bac name, length of match, percent identity
    #QUERY_NAME, HIT_NAME, HSP_LENGTH, IDENTICAL
    my %match_contigs_list;
    #group by contig name
    foreach my $result (@{$out})
    {
        my @keys =  ('QUERY_NAME','HIT_NAME','HSP_LENGTH','IDENTICAL');
        my %hash;
        %hash = map { $_ => $result->{$_} } @keys; 
        push @{$match_contigs_list{$result->{QUERY_NAME}}}, \%hash;    
    }
    #for each contig name sort multiple hits by length, percent identity
    foreach my $key (keys %match_contigs_list)
    {
        @{$match_contigs_list{$key}} = reverse sort comp_hits @{$match_contigs_list{$key}} if (@{$match_contigs_list{$key}} > 1);
    }
    #sort all contig group by length and percent identity of best matching hit for each contig
    my @list = reverse sort comp_hit_lists values %match_contigs_list;
    return \@list;
}

#functions for reading and writing contig map file
sub open_contig_map
{
    my ($self,$file_name) = @_;
    $self->error_message("$file_name does not exist.\n") and die unless -e $file_name;
    my $fh = Genome::Utility::FileSystem->open_file_for_reading($file_name);
    $self->error_message("Could not open contig map $file_name for reading.\n") and die unless defined $fh;
    my %contig_map;
    while(my $line = <$fh>)
    {
        chomp $line;
        my @tokens = split /\s+/,$line;
        next unless @tokens == 3;
        $contig_map{$tokens[0]} = { maps_to => $tokens[1], module => $tokens[2] };
    }
    return \%contig_map;
}

sub write_contig_map
{
    my ($self, $contig_map, $file_name) = @_;
    unlink $file_name if -e $file_name;
    my $fh = Genome::Utility::FileSystem->open_file_for_writing($file_name);
    $self->error_message("Could not open contig map $file_name for writing.\n") and die unless defined $fh;
    foreach my $contig_name (keys %{$contig_map})
    {
        my $hash_ref = $contig_map->{$contig_name};
        print $fh "$contig_name $hash_ref->{maps_to} $hash_ref->{module}\n";
    }
}

sub create_match_and_orphan_lists
{
    my ($self, $contig_map) = @_;
    my %match_list;
    my %orphan_list;
    foreach my $contig_name (keys %{$contig_map})
    {
        if($contig_map->{$contig_name}{maps_to} ne 'orphan_project')
        {
            $match_list{$contig_name} = $contig_map->{$contig_name};
        }
        else
        {
            $orphan_list{$contig_name} = $contig_map->{$contig_name};
        }
    }
    return (\%match_list, \%orphan_list);
}

sub get_contig_names
{
    my ($self, $ace_file_name) = @_;
    my $fh = Genome::Utility::FileSystem->open_file_for_reading($ace_file_name);
    $self->error_message("There was an error opening ace file $ace_file_name for reading.") and die unless defined $fh;
    my @contig_names;
    while(my $line = <$fh>)
    {
        if($line =~ /^CO /)
        {
            my @tokens = split /\s+/,$line;
            push @contig_names, $tokens[1];            
        }
    }
    return \@contig_names;
}

sub create_contig_map
{
    my ($self, $ace_file, $blastfile) = @_;

    $self->error_message("$blastfile does not exist") and die unless (-e $blastfile);
    my $out = Genome::Model::Tools::WuBlast::Parse->execute(blast_outfile => $blastfile);   
    $self->error_message("Failed to parse $blastfile") and die unless defined $out;

    $self->error_message("Ace file $ace_file does not exist") and die unless (-e $ace_file);    

    my $list = $self->get_matching_contigs_list($out->{result});$out=undef;

    my %contig_map;
    my $contig_names = $self->get_contig_names($ace_file);
    foreach my $contig (@{$contig_names})
    {
        $contig_map{$contig} = {maps_to => 'orphan_project', module => 'GetMatchingContigs'};        
    }
    foreach my $item (@{$list})
    {
        my $bac_name = $item->[0]{HIT_NAME};
        my $contig_name = $item->[0]{QUERY_NAME}; 
        $contig_map{$contig_name}->{maps_to} = $bac_name;
    }    
    return \%contig_map;
}

1;
