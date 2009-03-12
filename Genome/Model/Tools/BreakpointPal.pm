package Genome::Model::Tools::BreakpointPal;

use strict;
use warnings;
use Genome;
use GSCApp;

class Genome::Model::Tools::BreakpointPal {
    is => 'Command',                    
    has => [ # specify the command's properties (parameters) <--- 
	     breakpoint_id    => {
		 type         => 'String',
		 doc          => "give the breakpoint_id in this format chr11:36287905-36288124",
	     },
	     bp_flank         => {
		 type         => 'Number',
		 doc          => "give the number of bases you'd like for fasta's around the breakpoint [Default value is 300]",
		 is_optional  => 1,

	     },
	     pal_threshold    => {
		 type         => 'Number',
		 doc          => "give the pal threshold you'd like to use in your pal [Default value is 100]",
		 is_optional  => 1,

	     },
	         irx          => {
		 type         => 'String',
		 doc          => "give a quoted list of readpair  orientions or the single oriention you would like to use in order to pick primer pairs to resolve an interchromosomal rearangement [pp, pm, mp,or mm where p=plus and m=minus] [.eg pp means reads running from BP1 are in the plus orientation and reads from BP2 are also in the plus orientation] if there are read pairs supporting two or more readpair orientations the option would be used as ie --irx \"pp mp\"",
		 is_optional  => 1,

	     },
	         inv          => {
		 type         => 'Boolean',
		 doc          => "Using this flag will initiate picking 4 primer pairs that will be designed with the intent to resolve an inverted repeat",
		 is_optional  => 1,

	     },
	     max_pcr_product_size => {
		 type         => 'Number',
		 doc          => "Set this parameter if you'd like to specify a maximum length for the sequence that's used to design the PCR primers default is set to twice the flank which by default will be (2 x 300) or 600 ",
		 is_optional  => 1,
		 
	     },

	     ],
    
    
};


sub help_brief {                            # keep this to just a few words <---
    "This tool will make three fasta files from the Human NCBI build 36based on you breakpoint id and run a pal -all on them."                 
}

sub help_synopsis {                         # replace the text below with real examples <---
    return <<EOS

gt break-point-pal --breakpoint-id chr11:36287905-36288124
 
EOS
}

sub help_detail {                           # this is what the user will see with the longer version of help. <---
    return <<EOS 

running this breakpoint id with the default options
gt breakpoint-pal --breakpoint-id chr11:36287905-36288124

is the same as running

gt breakpoint-pal --breakpoint-id chr11:36287905-36288124 --bp-flank 300 --pal-threshold 100


which will result in 3 fasta files

chr11:36287905-36288124.BP1-2.fasta      is the fasta from 36287905 to 36288124 on chr11
chr11:36287905-36288124.BP1.300.fasta    300 flank either side of BP1 "36287905" 
      (5prime => 36287604-36287904 and 3prime => 36287905-36288205)
chr11:36287905-36288124.BP2.300.fasta    300 flank either side of BP2 "36288124" 
      (5prime => 36287823-36288123 and 3prime => 36288124-36288424)

and the result from the pal
chr11:36287905-36288124.BP1-2.fasta.BP2.pal100.ghostview

"pal -files chr12:36287905-36288124.BP1-2.fasta chr12:36287905-36288124.BP1.300.fasta chr12:36287905-36288124.BP2.300.fasta -s 100 -all -out chr12:36287905-36288124.BP1-2.fasta.BP2.pal100.ghostview"

EOS
}


sub execute {                               # replace with real execution logic.
    my $self = shift;
    my $bp_id = $self->breakpoint_id;
    my ($chromosome,$breakpoint1,$breakpoint2);

    unless ($bp_id) {die "please provide the breakpoint id\n";}
    if ($bp_id =~ /chr([\S]+)\:(\d+)\-(\d+)/) { 
	$chromosome = $1;
	$breakpoint1 = $2;
	$breakpoint2 = $3;
    } else { die "please check the format of your breakpoint id\n"; }

    
    my $flank = $self->bp_flank;
    unless ($flank) { $flank = 300; }
    my $pal_s = $self->pal_threshold;
    unless ($pal_s) { $pal_s = 100; }


    my $bpr = $breakpoint2 - $breakpoint1;
    unless ($bpr >= $flank) { warn "Breakpoint region is $bpr, less than your flank, your BP1 and BP2 fasta have sequence from overlapping coordinates\n"; }
    
####Fasta1
    
    my $fasta1 = "$bp_id.BP1-2.fasta";
    open(FA,">$fasta1");
    
    my $fasta1_seq = &get_ref_base($chromosome,$breakpoint1,$breakpoint2);
    
    print FA qq(>$fasta1 NCBI Build 36, Chr:$chromosome, Coords $breakpoint1-$breakpoint2, Ori (+)\n);
    print FA qq($fasta1_seq\n);
    
    close(FA);
    
####Fasta2
    
    my $fasta2 = "$bp_id.BP1.$flank.fasta";
    open(FA2,">$fasta2");
    
    my $lt_stop1 = $breakpoint1 - 1;
    my $lt_start1 = $lt_stop1 - $flank;
    my $fasta2_lt_seq = &get_ref_base($chromosome,$lt_start1,$lt_stop1);
    
    print FA2 qq(>BP1.5prime.fasta $flank.$fasta1 NCBI Build 36, Chr:$chromosome, Coords $lt_start1-$lt_stop1, Ori (+)\n);
    print FA2 qq($fasta2_lt_seq\n);
    
    my $rt_start1 = $breakpoint1;
    my $rt_stop1 = $rt_start1 + $flank;
    my $fasta2_rt_seq = &get_ref_base($chromosome,$rt_start1,$rt_stop1);
    
    print FA2 qq(>BP1.3prime.fasta $flank.$fasta1 NCBI Build 36, Chr:$chromosome, Coords $rt_start1-$rt_stop1, Ori (+)\n);
    print FA2 qq($fasta2_rt_seq\n);
    
    close(FA2);
    
######Fasta3
    
    my $fasta3 = "$bp_id.BP2.$flank.fasta";
    open(FA3,">$fasta3");
    
    my $lt_stop2 = $breakpoint2 - 1;
    my $lt_start2 = $lt_stop2 - $flank;
    my $fasta3_lt_seq = &get_ref_base($chromosome,$lt_start2,$lt_stop2);
    
    print FA3 qq(>BP2.5prime.fasta $flank.$fasta1 NCBI Build 36, Chr:$chromosome, Coords $lt_start2-$lt_stop2, Ori (+)\n);
    print FA3 qq($fasta3_lt_seq\n);
    
    my $rt_start2 = $breakpoint2;
    my $rt_stop2 = $rt_start2 + $flank;
    my $fasta3_rt_seq = &get_ref_base($chromosome,$rt_start2,$rt_stop2);
    
    print FA3 qq(>BP2.3prime.fasta $flank.$fasta1 NCBI Build 36, Chr:$chromosome, Coords $rt_start2-$rt_stop2, Ori (+)\n);
    print FA3 qq($fasta3_rt_seq\n);
    
    close(FA3);
    
######PAL
    
    print qq(running\n\tpal -files $fasta1 $fasta2 $fasta3 -s $pal_s -all -out $fasta1.BP2.pal$pal_s.ghostview\n);
    system qq(pal -files $fasta1 $fasta2 $fasta3 -s $pal_s -all -out $bp_id.BP1-2.fasta$flank.pal$pal_s.ghostview);
    

######primer3 
    my $irx = $self->irx;
    my $inv = $self->inv;


    my @irx_primer_results;
    if ($irx) {
	@irx_primer_results = &get_irx_primer($bp_id,$irx,$flank,$self);
    }
    my $inv_primer_results;
    if ($inv) {

	print qq(the --inv option is currently unavailable please try again later\n);
	#$inv_primer_results = &get_inv_primer($bp_id);
    }

    my $irx_primer_files;
    if (@irx_primer_results) {
	$irx_primer_files = join' ',@irx_primer_results;
	print qq(see primer picks in these files; $irx_primer_files\n);
    }
}


sub get_ref_base {

#used to generate the refseqs;
    use Bio::DB::Fasta;
    my $RefDir = "/gscmnt/sata180/info/medseq/biodb/shared/Hs_build36_mask1c/";
    my $refdb = Bio::DB::Fasta->new($RefDir);

    my ($chr_name,$chr_start,$chr_stop) = @_;
    my $seq = $refdb->seq($chr_name, $chr_start => $chr_stop);
    $seq =~ s/([\S]+)/\U$1/;

    if ($seq =~ /N/) {warn "your sequence has N in it\n";}

    return $seq;
    
}

sub get_irx_primer {

    my ($bp_id,$irx,$flank,$self) = @_;


    my $breakpoint_depth;
    my $max_pcr_product_size = $self->max_pcr_product_size;
    if ($max_pcr_product_size) {
	$breakpoint_depth = sprintf("%d",($max_pcr_product_size/2));
    } else {
	$breakpoint_depth = $flank;
    }

    my $read_pair_ori;
    my @irx_rpo = split(/[\s]+/,$irx);

    my @picks;
    my ($picks_pp,$picks_pm,$picks_mp,$picks_mm);
    for my $rpo (@irx_rpo) {
	my $primer_name = "$bp_id.irx.$breakpoint_depth.$rpo";
	my ($seq) = &get_irx_primer_design_seq($bp_id,$rpo,$flank,$breakpoint_depth);
	my $seq_l = length($seq);
	print qq(\nprimers for irx with readpair orientation $rpo will be pick from a sequence that is $seq_l bp in length\n\n);
	my $pick = &pick_primer($primer_name,$seq);

	push (@picks,$pick);

    }

    return(@picks); 
    #print qq(see $picks_pp, $picks_pm, $picks_mp, or $picks_mm for your primer pair info\n);
}

sub get_irx_primer_design_seq {

    my ($bp_id,$rpo,$flank,$breakpoint_depth) = @_;

    #my $bp_id = "chr11:36287905-36289124"; #$self->breakpoint_id;
    my ($chromosome,$breakpoint1,$breakpoint2);
    
    unless ($bp_id) {die "please provide the breakpoint id\n";}
    if ($bp_id =~ /chr([\S]+)\:(\d+)\-(\d+)/) { 
	$chromosome = $1;
	$breakpoint1 = $2;
	$breakpoint2 = $3;
    } else { die "please check the format of your breakpoint id\n"; }

    my $genome = GSC::Sequence::Genome->get(sequence_item_name => 'NCBI-human-build36');
    my $chr = $genome->get_chromosome($chromosome);
    
    my $bp12_diff = $breakpoint2 - $breakpoint1;

    if ($bp12_diff < 200) {
###	$breakpoint_depth = $bp12_diff;   ###This was left here incase later we want to adjust the sequence size based on the distance between BP1 and BP2
    }


    if ($rpo eq "pp") {
	my $seq1_pp_start = $breakpoint1 - $breakpoint_depth;
	my $seq1_pp_end = $breakpoint1;
	my $seq2_pp_start = $breakpoint2 - $breakpoint_depth;
	my $seq2_pp_end = $breakpoint2;
	
	my $seq1_pp = $chr->sequence_base_substring($seq1_pp_start, $seq1_pp_end);
    	my $seq2_pp = $chr->sequence_base_substring($seq2_pp_start, $seq2_pp_end);
	
	my $masked_seq1_pp = $chr->mask_snps_and_repeats(begin_position       => $seq1_pp_start, 
							 end_position         => $seq1_pp_end,
							 sequence_base_string => $seq1_pp);
	my $masked_seq2_pp = $chr->mask_snps_and_repeats(begin_position       => $seq2_pp_start, 
							 end_position         => $seq2_pp_end,
							 sequence_base_string => $seq2_pp);
	my $class = q(GSC::Sequence);
	my $masked_rev_seq2_pp = GSC::Sequence::reverse_complement($class, $masked_seq2_pp);
	
	my $seq_pp = "$masked_seq1_pp$masked_rev_seq2_pp";
	return ($seq_pp);
	
    }
    
    if ($rpo eq "pm") {
	my $seq1_pm_start = $breakpoint1 - $breakpoint_depth;
	my $seq1_pm_end = $breakpoint1;
	my $seq2_pm_start = $breakpoint2;
	my $seq2_pm_end = $breakpoint2 + $breakpoint_depth;
	
	my $seq1_pm = $chr->sequence_base_substring($seq1_pm_start, $seq1_pm_end);
    	my $seq2_pm = $chr->sequence_base_substring($seq2_pm_start, $seq2_pm_end);
	
	my $masked_seq1_pm = $chr->mask_snps_and_repeats(begin_position       => $seq1_pm_start, 
							 end_position         => $seq1_pm_end,
							 sequence_base_string => $seq1_pm);
	my $masked_seq2_pm = $chr->mask_snps_and_repeats(begin_position       => $seq2_pm_start, 
							 end_position         => $seq2_pm_end,
							 sequence_base_string => $seq2_pm);
	my $seq_pm = "$masked_seq1_pm$masked_seq2_pm";
	return ($seq_pm);
	
    }
    if ($rpo eq "mp") {

##it was thought that extra caution needs to be employed here to see that oligos will work if the region between BP1 and BP2 is small however, because these are thought to be repeats it is not necessary to divide the sequence

	my $bpd_1 = $breakpoint_depth;
	my $bpd_2 = $breakpoint_depth;

	if ($bp12_diff < 400) {   ###This was left here incase later we want to adjust the sequence size based on the distance between BP1 and BP2
	    my $half = $bp12_diff/2;
	    my $rounded_half = sprintf("%d",($bp12_diff/2));
	    if ($half == $rounded_half) {
###		$bpd_1 = $half;   
###		$bpd_2 = $half;   
	    } else {
###		$bpd_1 = $rounded_half - 1;
###		$bpd_2 = $rounded_half;
	    }
	}

	my $seq1_mp_start = $breakpoint1;
	my $seq1_mp_end = $breakpoint1 + $bpd_1;
	my $seq2_mp_start = $breakpoint2 - $bpd_2;
	my $seq2_mp_end = $breakpoint2;
	
	my $seq1_mp = $chr->sequence_base_substring($seq1_mp_start, $seq1_mp_end);
    	my $seq2_mp = $chr->sequence_base_substring($seq2_mp_start, $seq2_mp_end);
	
	my $masked_seq1_mp = $chr->mask_snps_and_repeats(begin_position       => $seq1_mp_start, 
							 end_position         => $seq1_mp_end,
							 sequence_base_string => $seq1_mp);
	my $masked_seq2_mp = $chr->mask_snps_and_repeats(begin_position       => $seq2_mp_start, 
							 end_position         => $seq2_mp_end,
							 sequence_base_string => $seq2_mp);

	#my $class = q(GSC::Sequence);
	#my $masked_rev_seq1_mp = GSC::Sequence::reverse_complement($class, $masked_seq1_mp);
	my $seq_mp = "$masked_seq2_mp$masked_seq1_mp";

	return ($seq_mp);
    }

    if ($rpo eq "mm") {
	my $seq1_mm_start = $breakpoint1;
	my $seq1_mm_end = $breakpoint1 + $breakpoint_depth;
	my $seq2_mm_start = $breakpoint2;
	my $seq2_mm_end = $breakpoint2 + $breakpoint_depth;

	my $seq1_mm = $chr->sequence_base_substring($seq1_mm_start, $seq1_mm_end);
    	my $seq2_mm = $chr->sequence_base_substring($seq2_mm_start, $seq2_mm_end);
	
	my $masked_seq1_mm = $chr->mask_snps_and_repeats(begin_position       => $seq1_mm_start, 
							 end_position         => $seq1_mm_end,
							 sequence_base_string => $seq1_mm);
	my $masked_seq2_mm = $chr->mask_snps_and_repeats(begin_position       => $seq2_mm_start, 
							 end_position         => $seq2_mm_end,
							 sequence_base_string => $seq2_mm);

	my $class = q(GSC::Sequence);
	my $masked_rev_seq2_mm = GSC::Sequence::reverse_complement($class, $masked_seq2_mm);

	my $seq_mm = "$masked_rev_seq2_mm$masked_seq1_mm";
	return ($seq_mm);
    }
}

sub pick_primer {

    my ($id,$seq) = @_;
    my $length = length($seq);

    my $boundary = sprintf("%d",(($length/2) - 1));  #exonstart ==> boundary
    my $boundary_size = 3;

    my $includestart; ##not using this parameter
    my $includesize; ##not using this parameter
    my $excludestart; ##not using this parameter
    my $excludesize; ##not using this parameter


    my $product_range = "150-850"; #150-250 100-300 301-400 401-500 501-600 601-700 701-850 
    my $product_opt_size = "400";

    my $tm_min = 45;
    my $tm_max = 65;
    my $tm_opt = 60;
    my $tm_max_diff = 2; 
    my $product_tm_max = 120;
    my $ppoly_max = 3; #AAA

    my $psize_max = 27;
    my $psize_min = 20;
    my $psize_opt = 22;

    my $gc_max = 70;
    my $gc_min = 40;
    my $gc_opt = 50;

    my $gc_clamp = 2;

    open(OUT, ">primer3.parameters");
    print OUT qq(PRIMER SEQUENCE ID=$id\n);
    print OUT qq(SEQUENCE=$seq\n);
    print OUT qq(TARGET=$boundary, $boundary_size\n);  #E.g. 50,2 requires primers to surround the 2 bases at positions 50 and 51. Or mark the source sequence  with [ and ]: e.g. ...ATCT[CCCC]TCAT.. means that primers must flank the central CCCC.

    #print OUT qq(INCLUDED_REGION=$includestart, $includesize\n); #E.g. 20,400: only pick primers in the 400 base region starting at position 20.
    #print OUT qq(EXCLUDED_REGION=$excludestart, $excludesize\n); #E.g. 401,7 68,3 forbids selection of primers in the 7 bases starting at 401 and the 3 bases at 68. Or mark the source sequence  with < and >: e.g. ...ATCT<CCCC>TCAT.. forbids primers in the central CCCC.
    print OUT qq(PRIMER_NUM_RETURN=10\n);
    print OUT qq(PRIMER_PRODUCT_SIZE_RANGE=$product_range\n);
    print OUT qq(PRIMER_PRODUCT_OPT_SIZE=$product_opt_size\n);
    print OUT qq(PRIMER_MAX_TM=$tm_max\nPRIMER_MIN_TM=$tm_min\nPRIMER_OPT_TM=$tm_opt\n);
    print OUT qq(PRIMER_MAX_DIFF_TM=$tm_max_diff\n);
    print OUT qq(PRIMER_PRODUCT_MAX_TM=$product_tm_max\n);
    print OUT qq(PRIMER_MAX_POLY_X=$ppoly_max\n);
    print OUT qq(PRIMER_MAX_SIZE=$psize_max\nPRIMER_MIN_SIZE=$psize_min\nPRIMER_OPT_SIZE=$psize_opt\n);
    print OUT qq(PRIMER_MAX_GC=$gc_max\nPRIMER_MIN_GC=$gc_min\nPRIMER_OPT_GC=$gc_opt\n);
    print OUT qq(PRIMER_GC_CLAMP=$gc_clamp\n);
    print OUT qq(PRIMER_PAIR_COMPL_ANY=4\n);

    print OUT qq(PRIMER_EXPLAIN_FLAG=1\n);
    print OUT qq(=\n);
    close(OUT);
#Max Complementarity
#Max 3\' Complementarity

    my $file = "$id.primer3.result";
    system ("cat primer3.parameters | primer3 > $file"); 
    system qq(rm primer3.parameters);

    my $result = &blastprimer3result($id,$file);
    system qq(rm $file);

    return ($result);


}

sub blastprimer3result {

    my ($id,$pd_result) = @_;
    open(RESULT,"$pd_result");
    my $out = "$id.primer3.blast.result";
    open(OUT,">$out");
    while (<RESULT>) {
	chomp;
	my $line = $_;
	if ($line =~ /(PRIMER\_\S+\_SEQUENCE)\=(\S+)/) {
	    my $pid = $1;
	    my $p_seq = $2;
	    open(PF,">$pid.fasta");
	    print PF qq(>$pid.fasta\n$p_seq\n);
	    my $s = length($p_seq);
	    my $n = $s + $s;
	    system qq(blastn /gscmnt/200/medseq/analysis/software/resources/B36/HS36.fa $pid.fasta -nogap -M=1 -N=-$n -S2=$s -S=$s | blast2gll -s > $pid.out);

	    #system qq(blastn /gscmnt/200/medseq/analysis/software/resources/B36/HS36.fa $pid.fasta -M=1 -N=-3 Q=3 R=1 | blast2gll -s > $pid.out);

	    my $file = "$pid.out";
	    my ($hit_count,$loc) = &count_blast_hits($file);

	    system qq(rm $pid.fasta);
	    system qq(rm $file);
	    
	    print OUT qq($line\n);
	    print OUT qq($pid\_BLAST_HIT_COUNT=$hit_count\n);
	    print OUT qq($pid\_BLAST_HIT_LOCATION=$loc\n);

	} else {

	    print OUT qq($line\n);

	}
    }

    return($out);

}

sub count_blast_hits {

    my ($blastout) = @_;
    open(IN,$blastout);
    my $blast_hit_counts=0;
    my $location;
    while (<IN>) {
	chomp;
	my $line = $_;
	my (@sub_line) = split(/\;/,$line);
	my ($subject_id,$query_id,$subject_cov,$query_cov,$percent_identity,$bit_score,$p_value,$subject_length,$query_length,$alignment_bases,$HSPs) = split(/\s+/,$sub_line[0]);
	
	my $hsp_count = @sub_line;
	
	if ($location) {
	    my $loc1 = $location;
	    my ($loc) = $HSPs =~ /(\S+)\:/;
	    $location = "$loc1\:\:$subject_id($loc)";
	} else {
	    my ($loc) = $HSPs =~ /(\S+)\:/;
	    $location = "$subject_id($loc)";
	}
	
	for my $n (@sub_line) {
	    
	    my ($hit) = $n =~ /\((\S+)\)/;
	    $n =~ s/\s//gi;
	    if ($n =~ /^\d/) {
		unless ($location =~ /$n/) {

		    my $n1 = $location;
		    my ($loc) = $n =~ /(\S+)\:/;
		    $location = "$n1\:\:$subject_id($loc)";

		}
	    }
	    
	    while ($hsp_count > 1) {
		$hsp_count--;
		$blast_hit_counts++;
	    }
	}
    }
    return ($blast_hit_counts,$location);
}

