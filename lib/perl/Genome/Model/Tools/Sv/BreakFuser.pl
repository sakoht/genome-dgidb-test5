#!/gsc/bin/perl
# SVbreakpoint detects SVs from clusters of softclipped reads
# This is my implementation based on the idea SJ Jude teams

use strict;
use warnings;
use Getopt::Std;
use FindBin qw($Bin);
use lib "$FindBin::Bin";

my $version="SVbreakpoint-0.1r148";
my %opts = (q=>35,r=>2,k=>30,n=>3,c=>1,m=>3);
my %opts1;
getopts('o:q:r:k:n:c:l:m:ubdg:', \%opts1);
die("
Usage:   SVbreakpoint.pl <bams>
Options:
         -o STR   operate on comma-separated chromosome [all chromosome]
         -q INT   minimal mapping quality cutoff [$opts{q}]
         -r INT   minimal number of supporting read pairs [$opts{r}]
         -c INT   minimal motif/kmer coverage for constructing the graph [$opts{c}]
         -l STR   ignore breakpoints found in comma-separated library STRs
         -n INT   ignore breakpoints connected to more than [$opts{n}] other breakpoints
         -m INT   maximum number of mismatch allowed in aligned portion [$opts{m}]
         -k INT   Kmer size used to establish collection among breakpoints [$opts{k}]
         -g FILE   dump SVs and supporting reads in BED format for GBrowse
         -u       Output all the unilaterial Breakpoint Pairs
         -b       report read count by library
         -d       print out debug information
Version: $version
Contact: kchen\@genome.wustl.edu or xfan\@genome.wustl.edu\n
") unless (@ARGV);

my $options='';
foreach my $opt(keys %opts1){
  $options.='-'.$opt.$opts1{$opt};
  $opts{$opt}=$opts1{$opt};
}

#Recognize read group and reference sequence information from the bam headers
my %RG;
my %Libs;
my %Chrs;
foreach my $fbam(@ARGV){
  open(BAM,"samtools view -H $fbam |");
  while(<BAM>){
    if(/^\@RG/){  #getting RG=>LIB mapping from the bam header
      my ($id)=($_=~/ID\:(\S+)/);
      my ($lib)=($_=~/LB\:(\S+)/);
      my ($platform)=($_=~/PL\:(\S+)/);
#      my ($sample)=($_=~/SM\:(\S+)/);
#      my ($insertsize)=($_=~/PI\:(\d+)/);
      $lib=$fbam if(!defined $opts{b});
      $RG{$id}{lib}=$lib;
      $Libs{$lib}=1;
      $RG{$id}{platform}=$platform;
    }
    elsif(/^\@SQ/){
      my ($chr)=($_=~/SN\:(\S+)/);
      $Chrs{$chr}=1;
    }
  }
  close(BAM);
}

#Scheduling how bams are read by chromosome
my %viewbams;
my @chrs;
if($opts{o}){
  @chrs=split /\,/,$opts{o};
}
else{
  @chrs=sort byChromosome keys %Chrs;
}

foreach my $chr(@chrs){
  foreach my $fbam(@ARGV){
    push @{$viewbams{$chr}}, "samtools view $fbam $chr";
  }
}

printf "#%s %s %s\n",$version,$options,join(" ",@ARGV);
print "#Chr1\tPos1\tOrientation1\tChr2\tPos2\tOrientation2\tType\tSize\tScore\tnum_Reads\tnum_Reads_lib\n";
open(BED,">$opts{g}") if (defined $opts{g});

my %Breakpoint;
my %BKmotif;
my %BKreceptors;
my %BKMask;

foreach my $chr(@chrs){
  print "Read in chr$chr ...\n" if($opts{d});
  my %bkreads;
  my %breakpoint;
  foreach my $bamread (@{$viewbams{$chr}}){
    print "$bamread ... \n" if($opts{d});
    open(BAM,"$bamread |");
    my @tags;
    while(<BAM>){
      chomp;
      my $t;
      ($t->{readname},$t->{flag},$t->{chr},$t->{pos},$t->{mqual},$t->{cigar},$t->{mchr},$t->{mpos},$t->{isize},$t->{seq},$t->{qual},@tags)=split;
      next if($t->{flag} & 0x0400 ||
	      $t->{mqual}<$opts{q}
	     );
      next unless($t->{cigar}=~/S/i);  #properly mapped soft-clipped reads
      if(/NM\:i\:(\d+)/){
	$t->{NM}=$1;
      }
      next unless($t->{NM}<$opts{m});  #ignore reads with multiple mismatch in the aligned portion

      if(/RG\:Z\:(\S+)/){
	$t->{RG}=$1;
      }
      my $lib=(defined $t->{RG})?$RG{$t->{RG}}{lib}:'NA';
      my $bkpos;
      my $readlen=length($t->{seq});
      $t->{alnend}=$t->{pos}+$readlen-1;
      $t->{lib}=$lib;

      #Find Soft-clipped breakpoints
      #Assign motif from the end of the reads
      #Create receiptors from the entire soft-clipped reads
      if($t->{flag} & 0x10 && $t->{mpos}<$t->{pos} && $t->{cigar}=~/(\d+)M(\d+)S$/){
	my $mbase=$1;
	my $sbase=$2;
	$bkpos=join(':',$t->{chr},$t->{pos}+$mbase);
	if($sbase>=$opts{k}){
	  $breakpoint{$bkpos}++;
	  my $motif=uc substr $t->{seq},$readlen-$sbase,$opts{k};
	  $BKmotif{$motif}{$bkpos}{$lib}++;
	  $BKmotif{$motif}{$bkpos}{total}++;
	  push @{$BKmotif{$motif}{$bkpos}{reads}},$t;
	  $motif=~tr/ACGT/TGCA/; $motif=reverse $motif;
	  $BKmotif{$motif}{$bkpos}{$lib}++;
	  $BKmotif{$motif}{$bkpos}{total}++;
	  push @{$BKmotif{$motif}{$bkpos}{reads}},$t;
	  $BKMask{$bkpos}++ if(&Hit($lib));  #Register breakpoints specific to some libraries
	}
	#my $trimmed=substr $t->{seq},0,length($t->{seq})-$sbase;
	my $trimmed=$t->{seq};
	push @{$bkreads{$bkpos}},$trimmed;
      }
      elsif($t->{flag} & 0x20 && $t->{pos} < $t->{mpos} && $t->{cigar}=~/^(\d+)S\d+M/){
	my $sbase=$1;
	$bkpos=join(':',$t->{chr},$t->{pos});
	if($sbase>=$opts{k}){
	  $breakpoint{$bkpos}--;
	  my $motif=uc substr $t->{seq},0,$opts{k};
	  $BKmotif{$motif}{$bkpos}{$lib}++;
	  $BKmotif{$motif}{$bkpos}{total}++;
	  $motif=~tr/ACGT/TGCA/; $motif=reverse $motif;
	  $BKmotif{$motif}{$bkpos}{$lib}++;
	  $BKmotif{$motif}{$bkpos}{total}++;
	  push @{$BKmotif{$motif}{$bkpos}{reads}},$t;
	  $BKMask{$bkpos}++ if(&Hit($lib));  #Register breakpoints specific to some libraries
	}
	#my $trimmed=substr $t->{seq},$sbase;
	my $trimmed=$t->{seq};
	push @{$bkreads{$bkpos}},$trimmed;
      }
      else{
      }
    }
    close(BAM);
  }

  #Register Breakpoints
  my $newbreakpoints=0;
  foreach my $bkpos(keys %breakpoint){
    my %readseg;
    foreach my $read(@{$bkreads{$bkpos}}){
      #my $read=$t->{seq};
      #my $lib=(defined $t->{RG})?$RG{$t->{RG}}{lib}:'NA';
      #chop up reads
      my %seen_in_read;
      for(my $i=$opts{k};$i<length($read);$i++){
	my $motif1=uc substr $read,$i-$opts{k},$opts{k};
	my $motif2=reverse $motif1; $motif2=~tr/ACGT/TGCA/;
	$readseg{$motif1}++; $seen_in_read{$motif1}++;
	$readseg{$motif2}++; $seen_in_read{$motif2}++;
      }
      #remove repetitive receptor
      foreach my $motif(keys %seen_in_read){
	if($seen_in_read{$motif}>1){
	  delete $readseg{$motif};  #motif must be unique in a read
	}
      }
    }
    my $count=$breakpoint{$bkpos};
    my $ori=($count>0)?'+':'-';
    $count=abs($count);
    if($count>=$opts{r} &&  !defined $BKMask{$bkpos}){  #ignore not_well_supported/not_interested breakpoints
      $BKreceptors{$bkpos}=\%readseg;
      $Breakpoint{$bkpos}=$breakpoint{$bkpos};
      $newbreakpoints++;
    }
  }
  &BuildBreakPointNetwork($chr) if($newbreakpoints);
}
close(BED) if (defined $opts{g});


sub BuildBreakPointNetwork{
  my ($chr)=@_;
  my %BPG;  #Graph that contains connected breakpoints through motives (soft-clipped portion of the reads)
  my %BPGM;

  #Remove non-unique/singleton motives
  my @BKmotives=keys %BKmotif;
  #printf STDERR "#breakpoint motives:%d\n",$#BKmotives+1;
  foreach my $motif(@BKmotives){
    my @connections=keys %{$BKmotif{$motif}};
    if($#connections+1>=$opts{n}){  #non-unique
      delete $BKmotif{$motif};
    }
    else{
      foreach my $bkpos(keys %{$BKmotif{$motif}}){
	delete $BKmotif{$motif}{$bkpos} if($BKmotif{$motif}{$bkpos}{total}<$opts{c});  #must be seen at least $opts{c} times at a breakpoint
      }
    }
  }
  @BKmotives=keys %BKmotif;
  #printf STDERR "#unique breakpoint motives:%d\n",$#BKmotives+1;

  #Build Breakpoint Network
  foreach my $end(keys %BKreceptors){
    my %readseg=%{$BKreceptors{$end}};
    foreach my $motif(keys %readseg){
      if(defined $BKmotif{$motif}){
	my @starts=keys %{$BKmotif{$motif}};
	foreach my $start(@starts){
	  next if($end eq $start ||
		  !defined $Breakpoint{$start}		
		 );
	  my ($chr1,$pos1)=split /\:/,$end;
	  my ($chr2,$pos2)=split /\:/,$start;
	  next if(($Breakpoint{$start}*$Breakpoint{$end}>0) &&  #same orientation
		  abs($pos2-$pos1)<$opts{k});   #too close to each other

	  if(!defined $BPG{$start}{$end}{total} ||  # a new motif
	     $BPG{$start}{$end}{total}<$BKmotif{$motif}{$start}{total}){  # a more efficient motif
	    #$BPG{$start}{$end}=\%perlib;
	    $BPG{$start}{$end}=$BKmotif{$motif}{$start};
	  }
	  push @{$BPGM{$start}{$end}},$motif;
	}
      }
    }
  }

  #Dump results out of the SV network
  foreach my $start(sort bygenome keys %BPG){
    next unless(defined $Breakpoint{$start});
    my ($chr1,$pos1)=split /\:/,$start;
 #   next unless($chr1 eq $chr);
    foreach my $end(sort bygenome keys %{$BPG{$start}}){
      next unless(defined $Breakpoint{$end});
      my ($chr2,$pos2)=split /\:/,$end;
      next if( &GT($chr1,$chr2)>0 ||
	       $chr1 eq $chr2 && $pos1 > $pos2 );

      if(defined $BPG{$start}{$end}{total} && defined$BPG{$end}{$start}{total}) {  #reciprocal mapped
	my $max_Span_Reads=&Max($BPG{$start}{$end}{total},$BPG{$end}{$start}{total});
	if($max_Span_Reads>=$opts{r}){
	  my $ori1=($Breakpoint{$start}>0)?'+':'-';
	  my $ori2=($Breakpoint{$end}>0)?'+':'-';

	  my $score=99;
	  my $size=$pos2-$pos1;
	  my $type;
	  if($chr1 ne $chr2){
	    $type='CTX';
	    $size=100;
	  }
	  elsif($ori1 eq '+' && $ori2 eq '-'){
	    $type='DEL';
	  }
	  elsif($ori1 eq '+' && $ori2 eq '+' || $ori1 eq '-' && $ori2 eq '-'){
	    $type='INV';
	  }
	  elsif($ori1 eq '-' && $ori2 eq '+'){
	    $type='ITX';
	  }
	  else{
	    $type='UN';
	  }

	  my @libcount;
	  my $totalreads;
	  if($BPG{$start}{$end}{total}>$BPG{$end}{$start}{total}){
	    $totalreads=$BPG{$start}{$end}{total};
	    foreach my $lib(keys %Libs){
	      next unless(defined $BPG{$start}{$end}{$lib});
	      push @libcount,$lib . ':' . $BPG{$start}{$end}{$lib};
	    }
	  }
	  else{
	    $totalreads=$BPG{$end}{$start}{total};
	    foreach my $lib(keys %Libs){
	      next unless(defined $BPG{$end}{$start}{$lib});
	      push @libcount,$lib . ':' . $BPG{$end}{$start}{$lib};
	    }
	  }
	  printf "%s\t%d\t%d%s\t%s\t%d\t%d%s\t%s\t%d\t%d\t%d\t%s\n",$chr1,$pos1,abs($Breakpoint{$start}),$ori1,$chr2,$pos2,abs($Breakpoint{$end}),$ori2,$type,$size,$score,$totalreads,join('|',@libcount);
	
	  if($opts{g}){  #print out SV and supporting reads in BED format
	    # This only provides one SV breakpoints, not both
	    my $trackname=join('_',$chr1,$pos1,$type,$size);
	    printf BED "track name=%s  description=\"SVbreakpoint %s %d %s %d\" useScore=0\n",$trackname,$chr1,$pos1,$type,$size;
	    my @motives=@{$BPGM{$start}{$end}};
	    my $bestmotif=$motives[$#motives];
	    foreach my $t(@{$BKmotif{$bestmotif}{$start}{reads}}) {
	      my $ori=($t->{flag} & 0x10)?'-':'+';
	      my $color=($ori eq '+')?'255,0,0':'0,0,255';
	      printf BED "chr%s\t%d\t%d\t%s\t%d\t%s\t%d\t%d\t%s\n",$t->{chr},$t->{pos},$t->{alnend},join('|',$t->{readname},$t->{lib}),$t->{mqual},$ori,$t->{pos},$t->{alnend},$color;
	    }
	  }

	  #Release resolved breakpoints
	  foreach my $motif(@{$BPGM{$start}{$end}}){
	    delete $BKmotif{$motif}{$start};
	  }
	  foreach my $motif(@{$BPGM{$end}{$start}}){
	    delete $BKmotif{$motif}{$end};
	  }
	  delete $BPG{$start}{$end}; delete $BPG{$end}{$start};
	  delete $BPGM{$start}{$end}; delete $BPGM{$end}{$start};

	  my @ends=keys %{$BPG{$start}};
	  if($#ends<0){
	    delete $Breakpoint{$start};
	    delete $BKreceptors{$start};
	    delete $BKMask{$start};
	  }
	  my @starts=keys %{$BPG{$end}};
	  if($#starts<0){
	    delete $Breakpoint{$end};
	    delete $BKreceptors{$end};
	    delete $BKMask{$end};
	  }
	}
      }
      elsif($opts{u}){

      }
    }
  }
}

sub Max{
  my ($a,$b)=@_;
  $a=0 if(!defined $a);
  $b=0 if(!defined $b);
  return ($a>$b)?$a:$b;
}

sub Hit{
  my ($lib)=@_;
  my $hit=0;
  if(defined $opts{l}){
    foreach my $libstr(split /\,/,$opts{l}){
      $hit=1 if($lib=~/$libstr/i);
    }
  }
  return $hit;
}

sub GT{
  my ($chr1,$chr2)=@_;
  $chr1=~s/chr//;
  $chr2=~s/chr//;
  if($chr1=~/^\d+/ && $chr2=~/^\d+/){
    return $chr1 <=> $chr2;
  }
  elsif($chr1=~/^\w+/ && $chr2=~/^\w+/){
    return $chr1 cmp $chr2;
  }
  elsif($chr1=~/\w+/){
    return 1;
  }
  else{
    return 0;
  }
}

sub bygenome{
  my ($chr1,$pos1)=($a=~/(\S+)\:(\d+)/);
  my ($chr2,$pos2)=($b=~/(\S+)\:(\d+)/);
  $chr1=~s/chr//; $chr2=~s/chr//;
  if($chr1 eq $chr2){
    return $pos1 <=> $pos2;
  }
  else{
    return $chr1 cmp $chr2;
  }
}

sub byChromosome{
  my ($chr1,$chr2)=($a,$b);
  $chr1=~s/chr//; $chr2=~s/chr//;
  if($chr1=~/^\d+$/ && $chr2=~/^\d+$/){
    return $chr1 <=> $chr2;
  }
  elsif($chr1=~/\w+/ && $chr2=~/\w+/){
    return $chr1 cmp $chr2;
  }
  elsif($chr1=~/\w+/){
    $chr1=23;
    return $chr1 <=> $chr2;
  }
  else{
    $chr2=23;
    return $chr1 <=> $chr2;
  }
}
