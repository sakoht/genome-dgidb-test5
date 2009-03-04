package Genome::Model::Tools::Consed::TracesToConsed;

use strict;
use warnings;
use DBI;
use Compress::Zlib;
use Genome;
use GSCApp;


class Genome::Model::Tools::Consed::TracesToConsed {
    is => 'Command',                    
    has => [ # specify the command's properties (parameters) <--- 
	     chromosome       => {
		 type         => 'String',
		 doc          => "give the chromosome ie[1,2...22,X,Y",
	     },
	     start            => {
		 type         => 'Number',
		 doc          => "give the start coordinate",
	     },
	     trace_dir       => {
		 type         => 'String',
		 doc          => "give the full path to the traces you want to use in the assembly",
	     },


	     base_dir         => {
		 type         => 'String',
		 doc          => "give the full path to where you would like your new project to be built; unless given, your new assembly will be built in your current dir",
		 is_optional  => 1,
	     },
	     assembly_traces  => {
		 type         => 'String',
		 doc          => "provide a file of trace names you want assembled; unless the assembly_traces or amplicon option is used, all traces in the trace_dir will be attempted to be assembled",
		 is_optional  => 1,
	     },
	     amplicon         => {
		 type         => 'String',
		 doc          => "give a quoted list of amplicons or the single amplicon to id the reads in the read dir to be  assembled; to be used in place of an assembly traces fof; unless the assembly_traces or amplicon option is used, all traces in the trace_dir will be attempted to be assembled",
		 is_optional  => 1,
	     },
	     consedrc         => {
		 type         => 'String',
		 doc          => "give the full path to and including the .consedrc you want to use in building the assembly",
		 is_optional  => 1,
	     },
	     restrict_contigs => {
		 type         => 'Boolean',
		 doc          => "will make a .consedrc that will stipulate addNewReadsPutReadIntoItsOwnContig: never to use in building the assembly",
		 is_optional  => 1,
	     },
	     link_traces      => {
		 type         => 'Boolean',
		 doc          => 'use this option if you want a link to the trace rather than copying them to the chromat_dir',
		 is_optional  => 1,
	     },
	     stop             => {
		 type         => 'Number',
		 doc          => "give the end coordiante; unless this option is used, the ref will automaticly be extended 100bp on either side of the start",
		 is_optional  => 1,
	     },
	     extend_ref       => {
		 type         => 'Number',
		 doc          => "give the length in bp (ie;1000) to extend out from the start and end coordiantes; no need to use this option if basing project only from start",
		 is_optional  => 1,
	     },
	     project_details  => {
		 type         => 'string',
		 doc          => "provide a quoted comment to put in the refseq header",
		 is_optional  => 1,
	     },
	     project          => {
		 type         => 'string',
		 doc          => "provide a project name or use the default chromosome_start",
		 is_optional  => 1,
	     },
	     
	     ],
    
    
};



sub help_brief {                            # keep this to just a few words <---
    "This tool will make a consed ace file from a minimun of a directory of traces a chromosome and an NCBI build 36 chromosomal start coordinate"                 
}

sub help_synopsis {                         # replace the text below with real examples <---
    return <<EOS
gt consed traces-to-consed --chromosome --start --trace_dir

running...

gt consed traces-to-consed --chromosome 10 --start 126009345 --stop 126009576 --base_dir /gscmnt/238/medseq/human_misc/TEST --trace_dir /gscmnt/238/medseq/human_misc/TEST/chromat_dir/ --project_info 11+11-INS --extend_ref 1000

will produce the project 10_126009345 

EOS
}

sub help_detail {                           # this is what the user will see with the longer version of help. <---
    return <<EOS 


regardless of your intent for the assemblies, you may need to due some setup before running this script

==================================================================================================
--trace-dir is a mandatory parameter. 
All the traces you want to have assembled will need to be dumped and preferably zipped 	and placed in a	single location here after known as the traces dir. The traces dir canbe a mix of traces for several assemblies.

--link-traces will write a link in your projects chromat dir from the traces dir rather than following the default action; to copy the traces to the chromat dir
==================================================================================================
There are two options for selecting traces to be assembled into a project from the traces dir 

--assembly-traces is a user supplied traces.fof. If the trace name is in both the traces dir and this optional file, an attempt will be made to assemble it into the project your making.
--amplicon list the amplicon portion of the read name for the reads you want to assemble, if reads from more than one amplicon are to be assembled, list all the amplicons in a quoted string with a space between each amplicon ie "H_10_00fXo H_10_00fXa H_10_00fXb"

if neither of these two traces selection options are used, an attempt will be made to assemble all the traces in the traces dir in the project.
==================================================================================================
You have two options to help consed guide the addnewreads for you assembly

--consedrc you supply the full path to a .consedrc file you would like have in the edit_dir while making the assembly
--restrict-contigs this script will write a .consedrc file to the edit dir prior to and removing upon completion of the assembly that will limit the consed file to the one contig the reads are targeting 

if neither of these two options are used consed will follow it order of precidence to find a consedrc file
==================================================================================================

--base-dir if this option is not used the project your building will be built in you current location 

--extend-ref this option allows you to input the amout you want to subtract from the start position and to add to the stop position. If the --stop option is not used, the stop position will be the same as the start position and the ref will be extended out 1000bp in both directions unless --extend-ref is used. If a stop position is used then the refseq will go from start to stop unless --extend-ref is used.

--project-details is an option that allows you to put a relivent comment or info in the refseq header (ie, snp indel size bases ...)

--project default project name is chromosome_start this option would allow you to change that to anything "you'd" like (ie chromosome_start_stop); This will end up being the name tagged on the project directory, ace file, and refseq.

==================================================================================================

*Here are 4 examples of how this script was intened to be used. Fill in the appropriate values for the options used in these examples



building assemblies to be used by ==>  gt manual-review review-variants 

  if your reviewing snps, you could get by with the minimume requirements
 
       gt consed traces-to-consed --chromosome  --start --trace_dir 

  if your reviewing indels your minimum input would be 

       gt consed traces-to-consed --chromosome  --start --trace_dir --stop --extend-ref 1000 


                ======================================================


building assemblies to be used by detect-sequence-variation

       gt consed traces-to-consed --chromosome  --start --trace_dir --stop --base-dir --assembly-traces --restrict-contigs --link-traces --project 


                ======================================================


building assemblies to be used in the abbreviated Legacy pipeline

       gt consed traces-to-consed --chromosome  --start --trace_dir --stop --base-dir --extend-ref --project 


==================================================================================================

EOS
}


sub execute {                               # replace with real execution logic.
    my $self = shift;

    my $trace_dir = $self->trace_dir;
    unless (-e $trace_dir && -d $trace_dir) { die "check $trace_dir\n"; }

    my $base_dir = $self->base_dir;
    if ($base_dir) {
	unless (-e $base_dir && -d $base_dir) { die "check $base_dir\n"; }
    } else {
	$base_dir = `pwd`;
    }
    chdir ($base_dir);

    my $assembly_traces_fof = $self->assembly_traces;
    my $assembly_traces;
    if ($assembly_traces_fof && -e $assembly_traces_fof) {
	open(TFOF,$assembly_traces_fof);
	while (<TFOF>) {
	    chomp;
	    my $trace = $_;
	    $assembly_traces->{$trace}=1;
	}
    }

    my $amps;
    my $amplicons = $self->amplicon;
    if ($amplicons) {
	my @amps = split(/[\s]+/,$amplicons);
	my $n = @amps;
	if ($n == 1) {
	    $amps->{$amplicons}=1;
	}else {
	    for my $amp (@amps) {
		$amps->{$amp}=1;
	    }
	}
    }

    my $chromosome = $self->chromosome;
    my $start = $self->start;
    my $stop = $self->stop;
    unless ($stop) { $stop = $start; }

    my $project = $self->project;
    unless ($project) {$project = "$chromosome\_$start";}

    my $extend_ref = $self->extend_ref;
    if ($start eq $stop) {unless ($extend_ref) {$extend_ref=1000;}}
    unless ($extend_ref) {$extend_ref=0;}

    my ($ref_start,$ref_stop,);
    if ($start < $stop) {
	$ref_start= $start - 1000;
	$ref_stop= $stop + 1000;
    } else {
	$ref_start= $stop - 1000;
	$ref_stop= $start + 1000;
    }
    
    my $project_dir = "$base_dir/$project";
    my $chromat_dir = "$project_dir/chromat_dir";
    my $phd_dir = "$project_dir/phd_dir";
    my $poly_dir = "$project_dir/poly_dir";
    my $edit_dir = "$project_dir/edit_dir";
    
    unless (-e $project_dir && -d $project_dir) {system qq(mkdir $project_dir);}
    unless (-e $chromat_dir && -d $chromat_dir) {system qq(mkdir $chromat_dir);}
    unless (-e $phd_dir && -d $phd_dir) {system qq(mkdir $phd_dir);}
    unless (-e $poly_dir && -d $poly_dir) {system qq(mkdir $poly_dir);}
    unless (-e $edit_dir && -d $edit_dir) {system qq(mkdir $edit_dir);}
    
    my $project_details = $self->project_details;

    unless ($project_details) { $project_details = "$chromosome\:$start\_$stop"; }

    open(REF,">$edit_dir/$project.c1.refseq.fasta");
    print REF qq(>$project.c1.refseq.fasta $project_details NCBI Build 36, Chr:$chromosome, Coords $ref_start-$ref_stop, Ori (+)\n);
    my $sequence = &get_ref_base($chromosome,$ref_start,$ref_stop);
    print REF qq($sequence\n);
    close(REF);
    
    chdir($edit_dir);
    
    unless ("$project.c1.refseq.fasta" && -e "$project.c1.refseq.fasta") { die "no refseq file\n"; }
    
#fasta2phd <name of file with fasta> <quality value>
    
###system qq(/gsc/bin/mktrace $project.c1.refseq.fasta $project.c1);
###unless ("$project.c1" && -e "$project.c1") { warn "mktrace did not work\n"; system qq(touch $project.c1); }
###system qq(mv $project.c1 ../chromat_dir);
    
#system qq(consensus_raid -dir . -piece-type c -fasta $project.c1.refseq.fasta -quality-value 30 -root-name $project.c1);
    
    system qq(/gsc/scripts/bin/fasta2phd $project.c1.refseq.fasta 30);
    unless ("$project.c1.phd.1" && -e "$project.c1.phd.1") { die "no phd file\n"; }
    system qq(cp $project.c1.phd.1 ../phd_dir);
    
    
    system qq(phd2Ace $project.c1.phd.1);
    unless ("$project.c1.ace" && -e "$project.c1.ace") { die "no Ace file\n"; }
#system qq(cp $project.c1.ace $project.ace);
    my $egdfasta = "$project.c1.refseq.fasta";
    my $acefile = "$project.c1.ace";
    my $acenew = "$project.ace";
    
    mkdir ("../phd_dir",0775) if (! -d "../phd_dir");
    mkdir ("../chromat_dir",0775) if (! -d "../chromat_dir");
    my $chrln=<*.phd.1>;
    chomp($chrln);
    $chrln=~s/.phd.1//;
    system ("cat $chrln.phd.1|sed \'s/CHROMAT_FILE: none/CHROMAT_FILE: $chrln/\'>$chrln.phd.1.tmp");
    system ("\\mv $chrln.phd.1.tmp $chrln.phd.1");
    system ("cat $acefile|sed \'s/CHROMAT_FILE: none/CHROMAT_FILE: $chrln/\'> $acenew");
    #--- make fake trace file, then move to chromat_dir---
    system ("mktrace $egdfasta $chrln");;
    mkdir ("tmptrace.$$",0755);
    chdir ("tmptrace.$$");
    system ("\\cp ../$egdfasta .");
    system ("consensus_raid -dir .. -piece-type c -fasta $egdfasta -quality-value 30 -root-name $egdfasta");
    
    system ("\\mv ../$chrln.phd.1 .");
    system ("head -12 $chrln.phd.1 >$chrln.phd.1.tmp");
    system ("tail -\`wc -l ../phd_dir/$egdfasta.c1.phd.1|awk \'{print \$1-12}\'\` ../phd_dir/$egdfasta.c1.phd.1>>$chrln.phd.1.tmp");
    system ("mv $chrln.phd.1.tmp ../$chrln.phd.1");
    chdir ("..");
    system ("mv $chrln ../chromat_dir/$chrln");
    system ("mv *.c1.phd.1 ../phd_dir");
    system ("cp $egdfasta $chrln.refseq.fasta");
    system ("\\rm -rf tmptrace.$$");
    
    system ("rm phd_dir/*"); 
    system ("rm chromat_dir/*");
    system ("rmdir phd_dir");
    system ("rmdir chromat_dir");
    
    
    
    my %ampread;
    my $traces_fof = "$project_dir/traces.fof";
    my @amplist;
    
#my $amps; ## this will hold all the amplicons ided from parsing the read name and there build 36 coordinates
#opendir(TRACES,"/gscmnt/sata147/info/medseq/rmeyer/PROJECTS/projects/Kens_list/READS");

    my $link_traces = $self->link_traces;

    opendir(TRACES,"$trace_dir");
    open(FOF,">$traces_fof");
    while (my $trace = readdir(TRACES)) {
	
	next if ($trace eq "." || $trace eq "..");
	
	my $read;
	
	if ($trace =~ /(^\S+).gz/) {
	    $read = $1;
	} else {
	    $read = $trace;
	}
	
    #guide the reads from a traces fof provided by the user
	if ($assembly_traces->{$trace} || $assembly_traces->{$read}) {
	    unless ($trace =~ /\.gz$/) {system qq(gzip $trace_dir/$trace); $trace="$read.gz";}
	    
	    
	    if ($link_traces) {
		system qq(ln -s $trace_dir/$trace $chromat_dir/$trace);
	    } else {
		system qq(cp $trace_dir/$trace $chromat_dir);   
	    }
	    
	    my $amplicon;     #H _ 0 9 _ 0 0 e f q
	    if ($read =~ /PCR(H\_\S\S\_\S\S\S\S\S)\S+/) {
		$amplicon = $1;
	    } else {
		($amplicon) = $read =~ /PCR(\S\S\S\S\S\S\S\_\S\S\S)\S+/; #substr($trace,13,11);
	    }
	    
	    if ($amplicon) {
		push @{$ampread{$amplicon}},$read;
		push (@amplist,$amplicon);
	    }
	    
	    print FOF qq($read\n);
	    system qq(/gsc/scripts/bin/phred -dd $poly_dir -pd $phd_dir $chromat_dir/$read.gz);
	
	} elsif ($amplicons) {
	    foreach my $amplicon (sort keys %{$amps}) {
		if ($read =~ /$amplicon/) {
		    
		    unless ($trace =~ /\.gz$/) {system qq(gzip $trace_dir/$trace); $trace="$read.gz";}
		    
		    if ($link_traces) {
			system qq(ln -s $trace_dir/$trace $chromat_dir/$trace);
		    } else {
			system qq(cp $trace_dir/$trace $chromat_dir);   
		    }
		    
		    push @{$ampread{$amplicon}},$read;
		    push (@amplist,$amplicon);
		    
		    print FOF qq($read\n);
		    system qq(/gsc/scripts/bin/phred -dd $poly_dir -pd $phd_dir $chromat_dir/$read.gz);
		}
	    }
	} else {
	    
	    unless ($trace =~ /\.gz$/) {system qq(gzip $trace_dir/$trace); $trace="$read.gz";}
	    
	    if ($link_traces) {
		system qq(ln -s $trace_dir/$trace $chromat_dir/$trace);
	    } else {
		system qq(cp $trace_dir/$trace $chromat_dir);   
	    }
	    my $amplicon;     #H _ 0 9 _ 0 0 e f q
	    if ($read =~ /PCR(H\_\S\S\_\S\S\S\S\S)\S+/) {
		$amplicon = $1;
	    } else {
		($amplicon) = $read =~ /PCR(\S\S\S\S\S\S\S\_\S\S\S)\S+/; #substr($trace,13,11);
	    }
	    
	    if ($amplicon) {
		push @{$ampread{$amplicon}},$read;
		push (@amplist,$amplicon);
	    }
	    
	    print FOF qq($read\n);
	    system qq(/gsc/scripts/bin/phred -dd $poly_dir -pd $phd_dir $chromat_dir/$read.gz);
	    
	}
    }
    
    close(FOF);
    
    
#--- Get data from oltp  ---
    my %seqid=&get_oltp(@amplist);
    
#--- Get amplicon sequences from DW (write to __AMP__) ---
    &get_dw(%seqid);
    
#--- Create fasta file from phd file for each amp for screening ---
    &make_read_fasta(%ampread);
    
#--- screen fasta file ----
    &screen_mp(@amplist);
    
    my $consedrc = $self->consedrc;
    my $restrict_contigs = $self->restrict_contigs;
    my $move;
    if ($consedrc || $restrict_contigs) {

	if(-e "$project_dir/edit_dir/.consedrc" ) {
	    system ("mv $project_dir/edit_dir/.consedrc $project_dir/edit_dir/.consedrc.orig");
	    $move=1;
	}
    
    
	if ($consedrc) {
	    system qq(cp $consedrc $edit_dir);
	} else {
	    open(C,">$project_dir/edit_dir/.consedrc") || warn "no consedrc file\n" ;
	    print C "consed.addNewReadsPutReadIntoItsOwnContig: never\n";
	    print C "consed.addNewReadsRecalculateConsensusQuality: false\n";
	    close(C);
	}
    }
    
    system qq(consed_auto -ace $project.ace -addNewReads ../traces.fof -newAceFilename $project.ace.1);
    
    #LSF: The new consed might fail if no read align to it.  Try the old consed.
    unless(-f "$project.ace.1") {
	system("consed_old  -ace $project.ace -addNewReads ../traces.fof -newAceFilename $project.ace.1");
    }
    
    if (-f "$project.ace.1") { print qq($project.ace.1 successfully built\n); } else { print qq($project.ace.1 failed\n); }
    
    if ($consedrc || $restrict_contigs) {system qq(rm $edit_dir/.consedrc);}
    if ($move) {system ("mv $project_dir/edit_dir/.consedrc.orig $project_dir/edit_dir/.consedrc");}
    
    print qq(\n\ndone\n\n\n);
    return 1;
    
}



sub get_ref_base {

#used to generate the refseqs;
    use Bio::DB::Fasta;
    my $RefDir = "/gscmnt/sata180/info/medseq/biodb/shared/Hs_build36_mask1c/";
    my $refdb = Bio::DB::Fasta->new($RefDir);

    my ($chr_name,$chr_start,$chr_stop) = @_;
    my $seq = $refdb->seq($chr_name, $chr_start => $chr_stop);
    $seq =~ s/([\S]+)/\U$1/;
    return $seq;
    
}


sub screen_mp(@)
  {
    my (@amplist)=@_;
    
    foreach (@amplist) {
      chomp $_;
      #--- deal with each aplicon individually and then combine ---
      my $amp=$_;
      my $fasta=$amp.".fasta";
      my $qual=$amp.".fasta.qual";
      my $ampseq=$amp."_amp.seq";
      my $primseq=$amp."_primer.seq";

      my ($name,$fname,$base);
      my (%seq,%fulln,%lclip,%rclip,%leng)=();
      my (@line,@forder)=();
      my $amplen=`/gsc/bin/seqlen __AMP__/$ampseq`;
      chomp($amplen);

      #--- Read fasta file in hash ---
      open (F,"<__FASTA__/$fasta")|| die "Can not open file __FASTA__/",$fasta," for reading\n";
      my $bool=0;
      while (<F>) {
	if (/^>/) {
	  if ($bool==1) { #-- name is set --
	    $seq{$name}=$base;
	    $leng{$name}=length($base);
	  }
	  $name=$_;
	  $fname=$_;
	  chomp($fname);
	  $name=(split(/\s+/,$name))[0]; #--- Just get read name ---
	  $name=~s/>//; #--- remove fasta designation ---
	  $fulln{$name}=$fname;
	  push @forder,$name;
	  $base=""; #--- Null out base ---
	  $bool=1; 
	}else {
	  chomp; #--- remove eol ---
	  tr/[a-z]/[A-Z]/; #--- upper case it all, make pretty ---
	  $base.=$_;
	}
      }
      $seq{$name}=$base; #--- deals with the last instance ---
      $leng{$name}=length($base);
      close(F);
      
      #--- Screen with primer file first ---
      system ("(/gsc/bin/cross_match __FASTA__/$fasta __AMP__/$primseq -minmatch 10 -minscore 30 -penalty -2 >__FASTA__/$amp.primscreen.cross) 2> /dev/null");
      
      #--- Screen with amplicon ---
      system ("(/gsc/bin/cross_match __FASTA__/$fasta __AMP__/$ampseq -minmatch 30 -minscore 60 -penalty -2 >__FASTA__/$amp.ampscreen.cross) 2>/dev/null");

      #--- Deal with primer matches first ---
      open (P,"<__FASTA__/$amp.primscreen.cross");     
      while (<P>) {
	next unless /\(\d+\).*\(\d+\)/;
	tr/()//d;
	@line=split;
	#--- col5=name col6=left-pos col7=right-pos ---
	if ($line[6]<100) {
	  $lclip{$line[4]}=$line[5]."-".$line[6]."-primer";
	}else {
	  $rclip{$line[4]}=$line[5]."-".$line[6]."-primer";
	}	
	@line=(); #--- null out for next match --
      }
      close(P);
      
      #--- read the amp file ---
      open (A,"<__FASTA__/$amp.ampscreen.cross");
      while (<A>) {
	next unless /\(\d+\).*\(\d+\)/;
	tr/()//d;
	@line=split;
	#--- col5=name col6=left-pos col7=right-pos ---
	#---- deal with left side first and then right side ---
	if (! exists $lclip{$line[4]}) {	  
	  my $rpos;
	  $rpos=($line[5]-$line[9])+1 if $#line==11;
	  #--- if the match is the complement ---
	  #--- this gives you length till end ---
	  my $lm=$amplen-$line[11] if $#line==12; 	  
	  $rpos=($line[5]-$lm)+1 if $#line==12;
	  $rpos=1 if ($rpos<=0);
	  $lclip{$line[4]}="1-".$rpos."-amp";
	}
	if (! exists $rclip{$line[4]}) {
	  my ($lpos,$rm);
	  $rm=$amplen-$line[10] if $#line==11;
	  $rm=$line[12] if $#line==12;
	  $lpos=$line[6]+$rm;
	  $rclip{$line[4]}=$lpos."-".$leng{$line[4]}."-amp";
	}
      }
      close(A);

      #--- So we now have a left clip and a right clip ---
      #---- Make the screen file ----
      open (OS,">__FASTA__/$fasta.screen") || die "Could not open ",$fasta,".screen file for writing in __FASTA__\n";
      open (NFO,">__FASTA__/$fasta.nfo")|| die "Could not open ",$fasta,".nfo file for writing in __FASTA__\n";
      my $cdate=`date +%m/%d/%y\" \"%H:%M:%S`;
      chomp($cdate);
      foreach (@forder) {
	my $name=$_;
	my ($lclp,$rclp);
	#--- Open the phd file and add tags ---
	my $phd=$_.".phd.1";
	open (PHD,">>../phd_dir/$phd");
	my @b=split(//,$seq{$name});
	#--- left clipping first ---
	$lclp=0;
	if (exists $lclip{$name}) {
	  #--- lclip is in the format of lpos-rpos-tag ---
	  my @l=split(/-/,$lclip{$name});
	  for (my $i=0;$i<=$l[1]-2;$i++) {
	    splice(@b,$i,1,"X");
	  }
	  $lclp=$l[1]-2 if ($l[1]>=2);
	  $lclp=$l[1] if ($l[1]<2);
	  print PHD "\n";
	  print PHD "BEGIN_TAG\n";
	  print PHD "TYPE: vector\n";
	  print PHD "SOURCE: mpfof2consed\n";
	  print PHD "UNPADDED_READ_POS: 1 ",$l[1],"\n";
	  print PHD "DATE: ",$cdate,"\n";
	  print PHD "END_TAG\n";
	  print PHD "\n";
	}
	$rclp=$#b;
	if (exists $rclip{$name}) {
	  my @l=split(/-/,$rclip{$name});
	  for (my $j=$l[0];$j<=$#b;$j++) {
	    splice(@b,$j,1,"X");
	  }
	  $rclp=$l[0];
	  if ($l[0]<$#b) {	    
	    print PHD "\n";
	    print PHD "BEGIN_TAG\n";
	    print PHD "TYPE: vector\n";
	    print PHD "SOURCE: mpfof2consed\n";	  
	    print PHD "UNPADDED_READ_POS: ",$l[0]," ",$#b+1,"\n";
	    print PHD "DATE: ",$cdate,"\n";
	    print PHD "END_TAG\n";
	    print PHD "\n";
	  }
	  close(PHD);	 
	}
	print NFO $name," ",$lclp," ",$rclp,"\n";
	#--- Make pretty ---
	my $bases=join("",@b);
	$bases=~ s/(.{50})/$1\n/g;
	chomp($bases);
	#--- write to screened file ---
	print OS $fulln{$name},"\n";
	print OS $bases,"\n";
      }
      close(OS);
      close(NFO);
    }
    system ("cat __FASTA__/*.nfo>__FASTA__/ALL_fasta.info");
    
}


sub make_read_fasta(%)
  {
   my (%ampread)=@_;
   mkdir ("__FASTA__",0775);
   my @amp=keys %ampread;
   foreach (@amp) {
     chomp($_);
     my $ampn=$_;
     my $fasta=$_.".fasta";
     my $qual=$fasta.".qual";
     my $fof=$_."._phd_.fof";

     #--- Create the phd fof ---
     open (F,">__FASTA__/$fof")||die "Could not write amplicon_phd_fof\n";
     foreach (@{$ampread{$ampn}}) {
       chomp;
       print F "../phd_dir/",$_,".phd.1\n";
     }
     close(F);

     #--- run phd2fasta to create fasta file ---
     system ("/gsc/bin/ewing_phd2fasta -if __FASTA__/$fof -os __FASTA__/$fasta -oq __FASTA__/$qual");     

   }
   
}

sub get_dw(%) {

    my (%seqid)=@_;
    my (%ampseq)=();
    my @ampid=keys %seqid;
    my $cwd=`pwd`;
    chomp ($cwd);
    
    #--- Make __AMP__ directory in the edit_dir ---
    mkdir ("__AMP__",0775) if (! -d "__AMP__");
    
    #----- ENV TEST ----
    $ENV{"TNS_ADMIN"}="/gsc/pkg/oracle/8.1/network/admin" if (! defined $ENV{"TNS_ADMIN"});
    $ENV{"ORACLE_HOME"}="/gsc/pkg/oracle/8.1" if (! defined $ENV{"ORACLE_HOME"});
    
    #--- oracle user/pwd ---
    my $user="gscguest";
    my $pwd="guest_dw";
    
    #--- Perform db connect ---
    my $dbh=DBI->connect('dbi:Oracle:dwrac',$user,$pwd,{AutoCommit => 0,RaiseError=>0,RowCacheSize=>0,ora_check_sql => 0});
    
    #--- Check for handle, retry and die if failed ---
    if (! $dbh) {
	$dbh=DBI->connect('dbi:Oracle:dwrac',$user,$pwd,{AutoCommit => 0,RaiseError=>0,RowCacheSize=>0,ora_check_sql => 0});
	die " Could not connect to OLTP database on 2 attempt, Quiting ... \n" if (! $dbh);
    }
    
    #--- Set handle to deal with blob ---
    $dbh->{'LongReadLen'}=1024*1024;
    $dbh->{'LongTruncOk'} =0;
    
    my ($sth,$seqval,$sequgz);
    
    my $sql="select SEQUENCE_BASE_STRING_GZ from sequence_base_string where seq_id=?";
    
    $sth=$dbh->prepare (qq{$sql})|| die "unable to prepare statement ",$sql," : ",$DBI::errstr,"\n";
    
    foreach (@ampid) {
	chomp;
	my $ampfasta=$_."_amp.seq";
	open (A,">__AMP__/$ampfasta")|| die "Could not open file ",$ampfasta," for writing\n";
	$sth->bind_columns (undef,\$seqval);
	$sth->execute($seqid{$_}) || die "unable to execute ",$sql," : ",$DBI::errstr,"\n";;
	$sth->fetch;
	if ($seqval) {
	    
	    $sequgz=Compress::Zlib::memGunzip($seqval);
	    $sequgz=~ s/-/N/g;
	    $sequgz=~ s/(.{50})/$1\n/g;
	    chomp $sequgz;
	    
	    #--- Create initial fasta file ----
	    print A ">$_\n";
	    print A $sequgz;
	}
	close(A);
	
	#--- null out variables ----
	undef $seqval;undef $sequgz;
    }
    
    #--- close cursor ---
    $sth->finish;
    
    #--- Disconnect ---
    $dbh->disconnect;
    
}



sub get_oltp(@) {
    my (@amplist)=@_;
    my (%seqid,%prime1,%prime2)=();
    
    #--- Create Amplicon directory ---
    mkdir ("__AMP__",0775) if (! -d "__AMP__");
    
    #----- ENV TEST ----
    $ENV{"TNS_ADMIN"}="/gsc/pkg/oracle/8.1/network/admin" if (! defined $ENV{"TNS_ADMIN"});
    $ENV{"ORACLE_HOME"}="/gsc/pkg/oracle/8.1" if (! defined $ENV{"ORACLE_HOME"});
    
    #--- oracle user/pwd ---
    my $user="gscguest";
    my $pwd="g_guest";
    
    #--- Perform db connect ---
    my $dbh=DBI->connect('dbi:Oracle:gscprod',$user,$pwd,{AutoCommit => 0,RaiseError=>0,RowCacheSize=>0,ora_check_sql => 0});
    
    #--- Check for handle, retry and die if failed ---
    if (! $dbh) {
	$dbh=DBI->connect('dbi:Oracle:gscprod',$user,$pwd,{AutoCommit => 0,RaiseError=>0,RowCacheSize=>0,ora_check_sql => 0});
	die " Could not connect to OLTP database on 2 attempt, Quiting ... \n" if (! $dbh);
    }
    
    #--- sql to get info from oltp using amplicon ---
    my $sql="select p1.primer_sequence,p2.primer_sequence,ref_seq_id from setup s,pcr_setup pcr,primers p1, primers p2 where pcr.pcr_setup_id = s.setup_id and s.setup_name = ? and p1.pri_id=pri_id_1 and p2.pri_id=pri_id_2";
    
    my ($sth,$p1seq,$p2seq,$rfid);
    
    $sth=$dbh->prepare(qq{$sql})|| die "Could not prepare statement ",$sql," : ",$DBI::errstr," \n";
    
    foreach (@amplist) {
	chomp;
	my $primfile=$_."_primer.seq";
	open (A,">__AMP__/$primfile")|| die "Could not open primer file for writing\n";
	$sth->bind_columns(undef,\$p1seq,\$p2seq,\$rfid);
	$sth->execute($_) || die "Unable to execute ",$sql," : ",$DBI::errstr,"\n";
	$sth->fetch;
	
	$seqid{$_}=$rfid if ($rfid);
	$prime1{$_}=$p1seq if ($p1seq);
	if ($p1seq) {
	    print A ">$_-Primer1\n";
	    print A $p1seq,"\n";
	}
	$prime2{$_}=$p2seq if ($p2seq);
	if ($p2seq) {
	    print A ">$_-Primer2\n";
	    print A $p2seq,"\n";
	}
	close(A);
	#--- null out variable, better safe than sorry ---
	undef $rfid;undef $p1seq;undef $p2seq;
    }
    
    #--- close cursor ---
    $sth->finish;
    
    #--- disconnect ---
    $dbh->disconnect;
    
    return %seqid;        
}
