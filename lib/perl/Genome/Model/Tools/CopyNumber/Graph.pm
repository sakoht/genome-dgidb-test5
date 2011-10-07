package Genome::Model::Tools::CopyNumber::Graph;

use strict;
use Genome;
use Cwd 'abs_path';
use IO::File;
use Getopt::Long;
use Statistics::R;
use File::Temp;
use DBI;
require Genome::Sys;

class Genome::Model::Tools::CopyNumber::Graph {
    is => 'Command',
    has => [
    output_dir => {
        is => 'String',
        is_optional => 0,
        doc => 'Directory containing output graphs.',
    },
    name => {
        is => 'String',
        is_optional => 1,
        doc => 'Name of the data to be processed. Any name that you like to call the data.',
    },
    chromosome => {
        is => 'String',
        is_optional => 0,
        doc => 'Chromosome of the data to be processed.',
    },
    start => {
        is => 'Integer',
        is_optional => 0,
        doc => 'The start position of the region of interest in the chromosome.',
    },
    end => {
        is => 'Integer',
        is_optional => 0,
        doc => 'The end position of the region of interest in the chromosome.',
    },
    tumor_bam_file => {
        is => 'String',
        is_optional => 1,
        doc => 'The bam file of the tumor. Should include the whole path. One of tumor and normal bam file and array data should be specified.',
    },	
    normal_bam_file => {
        is => 'String',
        is_optional => 1,
        doc => 'The bam file of the normal. Should include the whole path. One of tumor and normal bam file and array data should be specified.',
    },	
    array_file => {
    	is => 'String',
    	is_optional => 1,
    	doc => 'Array data (swt file generated by R). Ask Qunyuan or Ling for details. Should include the whole path.',
    },
    flanking_region => {
        is => 'Integer',
        is_optional => 1,
        default => 2,
        doc => 'How much longer the flanking region on each side should be as to the region of interest. By default it is set to be 5.',
    },	
    sliding_window => {
        is => 'Integer',
        is_optional => 1,
        default => 1000,
        doc => 'How many sites to count the read each time. By default it is set to be 1000.',
    },
    plot_array => {
    	type => 'Boolean',
    	is_optional => 1,
    	default =>  0,
    	doc => 'Whether to plot array data.',
    },
    plot_title => {
    	type => 'Boolean',
    	is_optional => 1,
    	default => 1,
    	doc => 'Whether to have a title.',
    },
    plot_subtitle => {
    	type => 'Boolean',
    	is_optional => 1,
    	default => 1,
    	doc => 'Whether to have a sub title.',
    },
    plot_annotation => {
    	type => 'Boolean',
    	is_optional => 1,
    	default => 1,
    	doc => 'Whether to have the annotation.',
    },
    plot_snp => {
    	type => 'Boolean',
    	is_optional => 1,
    	default => 0,
    	doc => 'Whether to plot snp.',
    },
    fix_y_limit => {
    	type => 'Boolean',
    	is_optional => 1,
    	default => 1,
    	doc => 'Whether to fix the y axis limit.',
    },
    ]
};

sub help_brief {
    "generate copy number graph via samtools given bam file or array file and positions"
}

sub help_detail {
    "This script will call samtools and count the read per sliding-window for the region expanded to the flanking region, and draw the graph with the annotations (segmental duplication, repeat mask, dgv, gene) on the bottom. You can draw the normal and tumor separately, or you can draw both as long as their bam files are given. If the array data is given, it will draw either only the array data/tumor/normal or both the tumor and array data or both the tumor and normal data. If bam file is given and plot-snp is chosen, the heterozygous snp will be shown on top of the annotation."
}

sub execute {
    my $self = shift;

    # process input arguments
    my $outputFigDir = $self->output_dir;
    `mkdir $outputFigDir` unless (-e "$outputFigDir");
    my $name = $self->name;
    my $chr = $self->chromosome;
    my $start = $self->start;
    my $end = $self->end;
    my $bam_tumor = $self->tumor_bam_file;
    my $bam_normal = $self->normal_bam_file;
    my $array = $self->array_file;
    my $multiple_neighbor = $self->flanking_region;
    my $slide = $self->sliding_window;
    my $isArray = $self->plot_array;
	my $isTitle = $self->plot_title;
	my $isSubTitle = $self->plot_subtitle;
	my $isAnnotation = $self->plot_annotation;
	my $isSnp = $self->plot_snp;
	my $isFixYAxisLimit = $self->fix_y_limit;
	
	if($isArray == 1 && $array !~/\S+/){
		die("Array data is to be plotted but no array file given.\n");
	}
	
	if($isSnp == 1 && (! -e "$bam_tumor") && (! -e "$bam_normal")){
		die("To plot snp but no bam file given.\n");
	} 
	
    # Process options.
    die("Input not fulfill the conditions. Please type 'gmt copy-number graph -h' to see the manual.\n") unless (-e "$bam_tumor" || -e "$bam_tumor" || $isArray == 1);

    #test architecture to make sure bam-window program can run (req. 64-bit)
    unless (`uname -a` =~ /x86_64/) {
        $self->error_message("Must run on a 64 bit machine");
        die;
    }
    
    my $outputFigDir = abs_path($outputFigDir);
    
    # connect to database
    my $dbh;
    if($isAnnotation == 1){
	    my $db = "ucsc";
    	my $user = "mgg_admin";
    	my $password = "c\@nc3r"; 
    	my $dataBase = "DBI:mysql:$db:mysql2";
    	$dbh = DBI->connect($dataBase, $user, $password) || die "ERROR: Could not connect to database: $! \n";
	}
    my $picName;
    my $table;

	# get the length of the chromosome
	my $length;
	my $length1;
	my $length2;
	if(-e "$bam_tumor"){
		$length1 = readChrLength($bam_tumor, $chr);
#		print "$length1";
	}	
	if(-e "$bam_normal"){
		$length2 = readChrLength($bam_normal, $chr);
	}
	if(-e "$bam_tumor" && -e "$bam_normal"){
		if($length1 < $length2){
			$length = $length1;
		}
		else{
			$length = $length2;
		}
	}
	elsif(-e "$bam_tumor"){
			$length = $length1;
	}
	else{
			$length = $length2;
	}
	
    # read the neighbors
    my $interval = int($end - $start);
    my $neighbor1_left = $start - $multiple_neighbor*$interval;
    if($neighbor1_left < 0){
    	$neighbor1_left = 0;
    }
    my $neighbor1_right = $start - 1;
    if($neighbor1_right < 0){
    	$neighbor1_right = 0;
    }
    my $neighbor2_left = $end + 1;
    if((-e "$bam_tumor" || -e "$bam_normal") && $neighbor2_left > $length){
    	$neighbor2_left = $length;
    }
    my $neighbor2_right = $end + $multiple_neighbor*$interval;
    if((-e "$bam_tumor" || -e "$bam_normal") && $neighbor2_right > $length){
    	$neighbor2_right = $length;
    }

    # Step 2: get samtools and write to a file
	my $system_tmp = 1;
	my $pileup_threshold = 30;

    # tumor
    my ($tmp_in, $tmp_outL, $tmp_outR, $tmp_pileup);
    my $tmp_in_name = "NA";
    my $tmp_outL_name = "NA";
    my $tmp_outR_name = "NA";
	my $tmp_pileup_name = "NA";
    if(-e "$bam_tumor"){
        if($system_tmp == 1){        
	        $tmp_in = File::Temp->new();
    	    $tmp_in_name = $tmp_in -> filename;
    	    $tmp_outL = File::Temp->new();
    	    $tmp_outL_name = $tmp_outL -> filename;
    	    $tmp_outR = File::Temp->new();
    	    $tmp_outR_name = $tmp_outR -> filename;
    	    if($isSnp == 1){
   		        $tmp_pileup = File::Temp->new();
	        	$tmp_pileup_name = $tmp_pileup -> filename;    	    
	        }
        }
        else{
    	    $tmp_in_name = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_in.csv";
    	    $tmp_outL_name = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_outL.csv";
    	    $tmp_outR_name = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_outR.csv";
       	    if($isSnp == 1){
	        	$tmp_pileup_name = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_pileup.csv";    	    
	        }
        }
        write_read_count($bam_tumor, $chr, $start, $end, $tmp_in_name, $slide);
        write_read_count($bam_tumor, $chr, $neighbor1_left, $neighbor1_right, $tmp_outL_name, $slide);  
        write_read_count($bam_tumor, $chr, $neighbor2_left, $neighbor2_right, $tmp_outR_name, $slide);
        
        if($isSnp == 1){
	        write_pileup($bam_tumor, $chr, $neighbor1_left, $neighbor2_right, $tmp_pileup_name, $pileup_threshold);
	    }
    }

    # normal
    my ($tmp_in_n, $tmp_outL_n, $tmp_outR_n, $tmp_pileup_n);
    my $tmp_in_name_n = "NA";
    my $tmp_outL_name_n = "NA";
    my $tmp_outR_name_n = "NA";
	my $tmp_pileup_name_n = "NA";
    if(-e "$bam_normal"){
        if($system_tmp == 1){    
	        $tmp_in_n = File::Temp->new();
	        $tmp_in_name_n = $tmp_in_n -> filename;
	        $tmp_outL_n = File::Temp->new();
	        $tmp_outL_name_n = $tmp_outL_n -> filename;
	        $tmp_outR_n = File::Temp->new();
	        $tmp_outR_name_n = $tmp_outR_n -> filename;
       	    if($isSnp == 1){
		        $tmp_pileup_n = File::Temp->new();
		        $tmp_pileup_name_n = $tmp_pileup_n -> filename;
		    }
	    }
        else{
        	$tmp_in_name_n = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_inN.csv";
        	$tmp_outL_name_n = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_outLN.csv";
        	$tmp_outR_name_n = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_outRN.csv";        
    	    if($isSnp == 1){
	        	$tmp_pileup_name_n = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_pileupN.csv";        	
	        }
        }

        write_read_count($bam_normal, $chr, $start, $end, $tmp_in_name_n, $slide);
        write_read_count($bam_normal, $chr, $neighbor1_left, $neighbor1_right, $tmp_outL_name_n, $slide);
        write_read_count($bam_normal, $chr, $neighbor2_left, $neighbor2_right, $tmp_outR_name_n, $slide);
        
        if($isSnp == 1){
	        write_pileup($bam_normal, $chr, $neighbor1_left, $neighbor2_right, $tmp_pileup_name_n, $pileup_threshold);
	    }
    }
    
    my $seg_file = "NA";
    my $rep_file = "NA";
    my $dgv_file = "NA";
    my $gene_file = "NA";    
if($isAnnotation == 1){
    # read the table and write to file temp_seg.csv
    # read annotation (segmentatl duplication), ready for printing in R
    $table = "genomicSuperDups";

    if($system_tmp == 1){    
	    my $seg = File::Temp->new();
    	$seg_file = $seg -> filename;    	
    }
    else{
    	$seg_file = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_seg.csv";    
    }
    my $seg_geneTableQuery = "SELECT chrom, chromStart, chromEnd FROM $table";
    readTable($dbh, $table, $chr, $neighbor1_left, $neighbor2_right, $seg_file, $seg_geneTableQuery);  

    # repeat mask
    $table = "chr".$chr."_rmsk";

    if($system_tmp == 1){        
	    my $rep = File::Temp->new();
	    $rep_file = $rep -> filename;
	}
	else{
	    $rep_file = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_rep.csv";    
	}
	my $rep_geneTableQuery = "SELECT genoName, genoStart, genoEnd FROM $table";
    readTable($dbh, $table, $chr, $neighbor1_left, $neighbor2_right, $rep_file, $rep_geneTableQuery); 

    # dgv
    $table = "dgv";

	if($system_tmp == 1){    
	    my $dgv = File::Temp->new();
	    $dgv_file = $dgv -> filename;
	}
	else{
		$dgv_file = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_dgv.csv";        
	}
    my $dgv_geneTableQuery = "SELECT chrom, chromStart, chromEnd FROM $table";    
    readTable($dbh, $table, $chr, $neighbor1_left, $neighbor2_right, $dgv_file, $dgv_geneTableQuery);

    # gene
    $table = "knownGene";

    if($system_tmp == 1){
	    my $gene = File::Temp->new();
    	$gene_file = $gene -> filename;
    }
    else{
    	$gene_file = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_gene.csv";        
    }
    my $gene_geneTableQuery = "SELECT chrom, txStart, txEnd FROM $table";
    readTable($dbh, $table, $chr, $neighbor1_left, $neighbor2_right, $gene_file, $gene_geneTableQuery);
}
	if($isAnnotation == 1){
	    # disconnect DBI
    	$dbh->disconnect();
    }

    # write the information to a file
    if($name !~/\S+/){
        $picName = $outputFigDir . "/Chr" . $chr . "_" . $start .  "_readcount_annotation.png";
    }
    else{
        $picName = $outputFigDir . "/". $name . "_chr" . $chr . "_" . $start .  "_readcount_annotation.png";
    }
    my $tmp_name;
    if($system_tmp == 1){
	    my $tmp_ = File::Temp->new();
    	$tmp_name = $tmp_ -> filename;
    }
    else{
    	$tmp_name = "/gscuser/xfan/svn/perl_modules/Genome/Model/Tools/Xian/tmp_name.csv";
    }

    open FILE_name, ">", $tmp_name or die $!;
    print FILE_name "$tmp_in_name\t$tmp_outL_name\t$tmp_outR_name\t$tmp_in_name_n\t$tmp_outL_name_n\t$tmp_outR_name_n\n$name\t$picName\t$chr\t$isTitle\t$isSubTitle\t$isAnnotation\n$start\t$end\t$neighbor1_left\t$neighbor1_right\t$neighbor2_left\t$neighbor2_right\n$seg_file\t$rep_file\t$dgv_file\t$gene_file\t$array\t$isArray\n$isSnp\t$tmp_pileup_name\t$tmp_pileup_name_n\t$isFixYAxisLimit\t\t\n";
    close FILE_name;
    # Step 3: Read the coverage depth using R 
    my $command = qq{readcount(name="$tmp_name")};
    my $library = "CN_graph.R";
    my $call = Genome::Model::Tools::R::CallR->create(command=>$command, library=>$library);
    $call -> execute;
    return 1;
}

sub write_read_count {
    my ($bam, $chr, $start, $end, $tmp_in_name, $slide) = @_;
    my @command = `samtools view $bam $chr:$start-$end`;
    open FILE_readcount, ">", $tmp_in_name or die $!;
    close FILE_readcount;
    open FILE_readcount, ">>", $tmp_in_name or die $!;

    # write read count
    my $current_window = $start;
    my $readcount_num = 0;
    for(my $i = 0; $i < $#command; $i ++ ) {
        my $each_line = $command[$i];
        my ($tmp1, $tmp2, $chr_here, $pos_here, $end_here,) = split(/\t/, $each_line);
        if($pos_here > $current_window + $slide){
        	if($readcount_num != 0){
            	print FILE_readcount "$chr\t$current_window\t$readcount_num\n";
            }
            if($current_window + $slide > $end){
                last;
            }
            $current_window += $slide;
            if($pos_here > $current_window + 2*$slide){
            	$readcount_num = 0;
            }
            else{
	            $readcount_num = 1;
	        }
        }
        else{
            $readcount_num ++;
        }
    } 
    if($current_window + $slide < $end){
    	while($current_window + $slide < $end){
    		$current_window += $slide;
    		print FILE_readcount "$chr\t$current_window\t0\n";
    	}
    }
    close FILE_readcount;
    return;
}

sub readTable {
    my ($dbh, $table, $myChr, $myStart, $myStop, $myAnoFile, $geneTableQuery) = @_;
    # query
    # my $geneTableQuery = "SELECT chrom, chromStart, chromEnd FROM $table";
    my $geneStatement = $dbh->prepare($geneTableQuery) || die "Could not prepare statement '$geneTableQuery': $DBI::errstr \n";

    # execute query
    my ($chr, $chrStart, $chrStop);
    
    my $subString = ",";

    open FILE, ">", $myAnoFile or die $!;
    print FILE "Start\tEnd\n";
    close FILE;
    open FILE, ">>", $myAnoFile or die $!;
    $geneStatement->execute() || die "Could not execute statement for table knownGene: $DBI::errstr \n";
    while ( ($chr, $chrStart, $chrStop) = $geneStatement->fetchrow_array() ) {
        if($chr eq "chr".$myChr && $chrStart <= $myStop && $chrStop >= $myStart){ # overlap
            if($chrStart < $myStart){
                #$chrStart = $myStart;
                my $iIndex = index($myStart, $subString);
                if($iIndex >= 1){
                	$chrStart = substr($myStart, 0, $iIndex-1);
                }
                else{
                	$chrStart = $myStart;
                }
            }
            if($chrStop > $myStop){
                $chrStop = $myStop;
            }
            print FILE "$chrStart\t$chrStop\n";
        }
    }
    close FILE;
}

sub write_pileup {
	my ($bam, $chr, $neighbor1_left, $neighbor2_right, $tmp_pileup_name, $pileup_threshold) = @_;
	
	my $tmp = File::Temp->new();
	my $tmp_name = $tmp -> filename;
	      
    my $human_ref = Genome::Config::reference_sequence_directory() . '/NCBI-human-build36/all_sequences.fa';
	my @command = `samtools view -uh $bam $chr:$neighbor1_left-$neighbor2_right | samtools pileup -cv -f $human_ref - > $tmp_name`;
	open FILE_pileup_raw, "<", $tmp_name or die $!;
	
    open FILE_pileup, ">", $tmp_pileup_name or die $!;
    close FILE_pileup;
    open FILE_pileup, ">>", $tmp_pileup_name or die $!;

    # write position
	while (my $each_line = <FILE_pileup_raw>) {
        my ($tmp1, $pos, $tmp2, $hap_new, $tmp3, $score,) = split(/\t/, $each_line);
        if($score > $pileup_threshold && $hap_new eq "K" || $hap_new eq "W" || $hap_new eq "M" || $hap_new eq "Y" || $hap_new eq "Y" || $hap_new eq "S"){
            print FILE_pileup "$pos\n";
        }
    } 
    close FILE_pileup_raw;
    close FILE_pileup;
    return;	
}

sub readChrLength{
    my ($bam, $chr) = @_;
	my @command = `samtools view -H $bam`;

    my $length;

	# skip the first two lines (first line: EOF; second line: header of the file)
	for(my $i = 1; $i < $#command; $i ++ ) {
        my $each_line = $command[$i];
        my ($tmp1, $chromosome_col, $length_col) = split(/\t/, $each_line);
        my ($tmp2, $chromosome) = split(/:/, $chromosome_col);
        if($chromosome eq $chr){
        	chomp $length_col;
        	(my $tmp3, $length) = split(/:/, $length_col);
	        last;
	    }
	}
	return $length;
}
