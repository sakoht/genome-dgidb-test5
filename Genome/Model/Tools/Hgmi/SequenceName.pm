package Genome::Model::Tools::Hgmi::SequenceName;

use strict;
use warnings;

use IO::File;
use File::Slurp;
use Cwd;
require "pwd.pl";
use Bio::SeqIO;
use Bio::Seq;
use Carp;


UR::Object::Type->define(
class_name => __PACKAGE__,
is => 'Command',
has => [
        'fasta' => { is => 'String',
                     doc => "fasta file" },
        'analysis_version' => { is => 'String',
                                doc => "Analysis version" },
        'locus_id' => { is => 'String',
                        doc => "Locus ID string" },
        'acedb_version' => { is => 'String',
                             doc => "Ace DB version" },
        ]


                         );

sub help_brief
{
    "tool for renaming sequences (HGMI Projects only!)";
}

sub help_synopsis
{
    my $self = shift;
    return <<"EOS"
This command is intended for use with HGMI projects only!
EOS
}

sub help_detail
{
    my $self = shift;
    return <<"EOS"
This command is intended for use with HGMI projects only!
EOS
}

sub execute
{
    my $self = shift;

    my @line = split(/\./,$self->fasta);

    my $revised_fasta = $line[0] = 'contigs';
    my $fasta = $line[1] = 'fasta';
    my $short_ver_num = $self->version_lookup($self->analysis_version);
    my $new = "newname";
    my $new_output_file = join(".",$self->locus_id,
                                   $short_ver_num,
                                   $line[0],
                                   $new,
                                   $line[1]);

    my $instream = new Bio::SeqIO(-file => $self->fasta, -format => 'fasta');
    my $outstream = new Bio::SeqIO(-file => ">$new_output_file",
                                   -format => 'fasta');

    my @seq_gcfile;

    while( my $seqobj = $instream->next_seq)
    {
        my $seq_id = $seqobj->primary_id();
        my $new_seq_id = join("_",$self->locus_id,$seq_id);
        push(@seq_gcfile, $new_seq_id);
        my $seq = $seqobj->seq;
        if ($seq =~ m/x/ix)
        {carp "\n\nWARNING this contig contains X's : $new_seq_id\n\n";}
        $seq = uc($seq);
        my $newseq = new Bio::Seq(-seq => $seq,
                                  -id => $new_seq_id
                                  );
        $outstream->write_seq($newseq);

    }

    # this dependence on being in the current directory 
    # needs to be fixed.
    my $cwd = getcwd();
    my @cwd = split(/\//x,$cwd);
    if($#cwd)
    {
        croak "the current working directory seems short,\nare you in the right place?";
    }
    my $hgmi_acedb_patha;
    # this should be cleaned up with a lookup for the V# to Version_#.0
#    if ($self->acedb_version eq 'V1') 
#    {
#        $hgmi_acedb_patha = "/gscmnt/278/analysis/HGMI/Acedb/Version_1.0/ace_files/" . 
#                            $self->locus_id;
    
#    } 
#    elsif ($self->acedb_version eq 'V2')
#    {
#        $hgmi_acedb_patha = "/gscmnt/278/analysis/HGMI/Acedb/Version_2.0/ace_files/" .
#                            $self->locus_id;
#    }

    my $acedb_version = $self->acedb_version;
    $acedb_version =~ s/V(\d)/Version_$1\.0/;
    $hgmi_acedb_patha = "/gscmnt/278/analysis/HGMI/Acedb/". $acedb_version . 
                        "/ace_files/". $self->locus_id;

    unless (-e $hgmi_acedb_patha)
    {
        mkdir qq{$hgmi_acedb_patha} 
	or croak "Can't make $hgmi_acedb_patha: $!\n";
    }

    my $newHGMIpath = $hgmi_acedb_patha."/".$self->analysis_version;

    unless (-e $newHGMIpath)
    {
        mkdir qq{$newHGMIpath}
	or croak "Can't make $newHGMIpath: $!\n";
    }

    my $hgmi_acedb_path = $newHGMIpath;

    my $Intergenic = join("\/",@cwd[0..7],'Gene_merging',$self->analysis_version,'Hybrid','intergenic');
    my $BAPseq = join("\/", @cwd[0..7],'BAP',$self->analysis_version,'Sequence');
    my $Ensemblseq = join("\/", @cwd[0..7],'Ensembl_pipeline',$self->analysis_version,'Sequence');
    my $Rfamseq = join("\/", @cwd[0..7],'Rfam',$self->analysis_version);

    # the presence of the symlink target should be
    # tested before creating the symlink
    symlink "$cwd/$new_output_file","$hgmi_acedb_path/$new_output_file";
    unless($! eq "File exists") # skip the "File exists" problem
    {
        croak "Can't make symlink path: $!\n";
    }
    # symlink OLDFILE,NEWFILE
    symlink "$cwd/$new_output_file","$Intergenic/$new_output_file"
        or croak "Can't make symlink path Intergenic: $!\n";
    symlink "$cwd/$new_output_file","$BAPseq/$new_output_file"
        or croak "Can't make symlink path BAP: $!\n";
    symlink "$cwd/$new_output_file","$Ensemblseq/$new_output_file"
        or croak "Can't make symlink path Ensembl: $!\n";
    symlink "$cwd/$new_output_file","$Rfamseq/$new_output_file"
        or croak "Can't make symlink path Rfam: $!\n";

    chdir($Rfamseq);
    my $cwd2 = getcwd();
    if(exists($ENV{HGMI_DEBUG}))
    {
        print "\n$cwd2\n\n";
    }

    chdir($hgmi_acedb_path);
    my $gc_file = "genomic_canonical.ace";
    my $new_gc_outfile = join(".",$self->locus_id,$gc_file);
    my @gc_outlines = ( );
    foreach my $gc_name (@seq_gcfile)
    {
        push(@gc_outlines,"Sequence $gc_name\n");
        push(@gc_outlines,"Genomic_canonical\n\n");
    }
    write_file($new_gc_outfile,@gc_outlines) or 
        croak "can't write to $new_gc_outfile: $!";;


    return 1;
}


sub version_lookup
{
    my $self = shift;
    my $v = shift;
    my $lookup = undef;
    my %version_lookup = ( 
		       'Version_1.0' => 'v1', 'Version_2.0' => 'v2',
		       'Version_3.0' => 'v3', 'Version_4.0' => 'v4',
		       'Version_5.0' => 'v5', 'Version_6.0' => 'v6',
		       'Version_7.0' => 'v7', 'Version_8.0' => 'v8',
		       );

    if(exists($version_lookup{$v}))
    {
        $lookup = $version_lookup{$v};
    }

    return $lookup;
}

1;
