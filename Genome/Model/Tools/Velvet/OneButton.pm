package Genome::Model::Tools::Velvet::OneButton;
use strict;
use warnings;

use Genome;
use IO::File;
use Data::Dumper;
use Getopt::Long;
use POSIX;
require File::Copy;

class Genome::Model::Tools::Velvet::OneButton {
    is => 'Command',
    has => [
        output_dir          => {    is => 'Text',
                                    doc => 'the directory for the results' 
                                }, #|o=s" => \$output_path, 

# made this optional like in original code
#       genome_len          => {    is => 'Integer',
#                                   doc => 'estimated genome length in bases'
#                               }, #|g=i" => \$genome_len, 

        hash_sizes          => {    is => 'Integer',
				    is_many => 1,
#				    default_value => [25,27.29],
	                        }, #|h=i{,}" => \@hash_sizes, 

# made optional
#        ins_length          => {    is => 'Integer',
#                                    doc => 'fragment length (average/estimated)'
#                                }, #|i=i" => \$ins_length, 

        version             => {    is => 'Text',
                                    default_value => '57-64',
                                    doc => 'the version of velvet to use'
                                }, #=s" => \$version

        file                => {    shell_args_position => 1,
                                    doc => 'the input fasta or fastq file'
                                },
    ],

    has_optional => [
	ins_length          => {    is => 'Integer',
                                    doc => 'fragment length (average/estimated)',
				    default_value => 280,
                                }, #|i=i" => \$ins_length, 

        genome_len          => {    is => 'Integer',
                                    doc => 'estimated genome length in bases',
				    default_value => 3000000,
                                }, #|g=i" => \$genome_len, 
	
        bound_enumeration   => {    is => 'Integer',
                                    doc => 'conduct binary search only if the number of candidates greater than b, or conduct enumeration',
				    default_value => 5,
	                        }, #|b=i" => \$enumeration_bound, 

        dev_ins_length      => {    is => 'Integer',
                                    doc => 'fragment length std deviation'
                                }, #|d=i" => \$ins_length_sd,  

        exp_covs            => {    is => 'Float', is_many => 1, }, #|e=f{,}" => \@exp_covs, 

        cov_cutoffs         => {    is => 'Float', is_many => 1, }, #|c=f{,}" => \@cov_cutoffs,
    ],
    doc => 'run velvet in a smart way (under conversion from initial script)'
};

sub help_synopsis {
    return <<EOS
gmt velvet one-button foo.fast[a|q] \
    [-o output_directory] \ 
    [-g genome_length] \
    [-h 31,33,35 ] \
    [-e exp_cov1 2,.. ] \
    [-c cov_cutoff1 2,.. ] \
    [-i insert_length] \
    [-d ins_length_sd] \
    [-b enumeration_bound] \
    [--version 57-64 #for velvet_0.7.57-64, only input the part behind velvet_0.7.);

ADD MORE EXAMPLES HERE!!!!
EOS
}

sub help_detail {
    return "A wrapper for running velvet based on the original oneButtonVelvet-3opts by Guohui Yao.\n\nCONVERSION STILL IN PROGRESS.  CONTACT INFORMATICS!"
}

sub execute {
    my $self = shift;

    unless ($self->_print_params_to_screen_and_logfile()) {
	$self->error_message("Failed to print params to screen and logfile");
	return;
    }

    #print read length and read count to log file .. that's all
    my ($read_length, $read_count) = $self->_get_input_read_count_and_length();
    $self->log_event("\#read length: $read_length\n\#number of reads: $read_count\n");
    
    #print .. to pass test stdout check
    my $file_format = $self->_resolve_input_file_format();
    print "read length: $read_length\nnumber of reads: $read_count\nFile format: ".
	$self->_resolve_input_file_format()."\n";

    my @hash_sizes = $self->_resolve_hash_sizes;
    if (@hash_sizes > $self->bound_enumeration) {
	#method returns array if successful but it's not needed
	unless ($self->_pick_best_hash_size(@hash_sizes)) {
	    $self->error_message("Failed to run _pick_best_hash_size with hash sizes: @hash_sizes");
	    return;
	}
    }
    else {
	#TODO - need description of what this does
	unless ($self->_enum_hash_size(@hash_sizes)) {
	    $self->error_message("Failed to run _enum_hash_size with hash sizes: @hash_sizes");
	    return;
	}
    }

    #print best results .. needed for test stdout check
    unless ($self->_print_best_values()) {
	$self->error_message("Failed to print best results");
	return;
    }

    #final velvet run with the derived best values
    unless ($self->_do_final_velvet_runs()) {
	$self->error_message("Failed to execute final velvet run with best values");
	return;
    }

    #remove screen_g file
    unlink $self->output_dir.'/screen_g';

    return 1;
}

sub _print_best_values {
    my $self = shift;

    unless (exists $self->{best_hash_size}) {
	$self->error_message("Best value for best_hash_size is missing");
	return;
    }

    unless (exists $self->{best_exp_coverage}) {
	$self->error_message("Best value for best_exp_coverage is missing");
	return;
    }

    unless (exists $self->{best_coverage_cutoff}) {
	$self->error_message("Best value for best coverage cutoff is missing");
	return;
    }

    unless ( @{$self->{best_n50_total}} ) {
	$self->error_message("Best values to n50 and total are missing");
	return;
    }

    my $txt = "The best result is: (hash_size exp_cov cov_cutoff n50 total)\n";
    $txt .= join( ' ',( $self->{best_hash_size}, $self->{best_exp_coverage}, $self->{best_coverage_cutoff}, @{$self->{best_n50_total}} ) );
    $txt .= "\n".`date`;

    print $txt;

    return 1;
}

sub _do_final_velvet_runs {
    my $self = shift;

    #params for velvet h
    my $velveth = $self->_version_path . $self->version .'/velveth';
    my $best_hash_size = $self->{best_hash_size};
    my $input_file_format = $self->{input_file_type};

    my $h_cmd = $velveth.' '.$self->output_dir.' '.$best_hash_size.' '.$input_file_format.' -shortPaired '.$self->file;

    if (system("$h_cmd")) {
	$self->error_message("Failed to run final velveth with command\n\t$h_cmd");
	return;
    }
    
    #params for velvet g
    my $velvetg = $self->_version_path . $self->version . '/velvetg';
    my $best_exp_cov = $self->{best_exp_coverage};
    my $best_cov_cf = $self->{best_coverage_cutoff};
    my $ins_length_sd = $self->_resolve_ins_length_sd();

    my $g_cmd = $velvetg.' '.$self->output_dir.' -exp_cov '.$best_exp_cov.' -cov_cutoff '.$best_cov_cf.' -ins_length '.$self->ins_length.' -ins_length_sd '.$ins_length_sd.' -read_trkg yes -min_contig_lgth 100 -amos_file yes';

    if (system("$g_cmd")) {
	$self->error_message("Failed to run final velvetg with command\n\t$g_cmd");
	return;
    }

    $self->log_event("$h_cmd\n$g_cmd\n");

    return 1;
}

sub _enum_hash_size {
    my ($self, @hash_sizes) = @_;
    foreach my $h (@hash_sizes) {
	#method return an array but it's not needed here
	unless ($self->_run_velveth_get_opt_expcov_covcutoff($h)) {
	    $self->error_message("Failed to run _run_velveth_get_opt_expcov_covcutoff with hash_size $h");
	    return;
	}
    }
    return 1;
}

sub _pick_best_hash_size { #doesn't actually return a hash size
    my ($self, @hash_sizes) = @_;

    #TODO check if hash sizes is always array of 3 numbers
    my $start = 0;
    my $end = $#hash_sizes;
    #for  @hash_sizes = (25,27,29,31,33,35,37,39,41);
    my $mid = POSIX::floor(0.5 * ($start + $end)); #33
    my $low = POSIX::floor(0.5 * ($start + $mid)); #29
    my $high = POSIX::ceil(0.5 * ($mid + $end));   #37
    
    my @mid_pair = (0, 0);
    my @low_pair = (0, 0);
    my @high_pair = (0, 0);

    @mid_pair = $self->_run_velveth_get_opt_expcov_covcutoff($hash_sizes[$mid]);

    while ($start < $end) {
	($start == $mid) ? (@low_pair = @mid_pair) : (@low_pair = (0, 0));
	($end == $mid) ? (@high_pair = @mid_pair) : (@high_pair = (0, 0));
	
	unless ($low_pair[0]) {
	    @low_pair = $self->_run_velveth_get_opt_expcov_covcutoff($hash_sizes[$low]);
	}
	if($self->_compare(@low_pair, @mid_pair) == 1) {
	    $end = $mid-1;
	    $mid = $low;
	    @mid_pair = @low_pair;
	}
	else {
	    unless ($high_pair[0]) {
		@high_pair = $self->_run_velveth_get_opt_expcov_covcutoff($hash_sizes[$high]);
	    }
	    if( ($self->_compare(@high_pair,@low_pair) == 1) or
		(($self->_compare(@high_pair,@mid_pair) == 0) and ($self->_compare(@low_pair,@mid_pair) == -1)) ){
		$start = $mid+1;
		$mid = $high;
		@mid_pair = @high_pair;
	    }elsif( ($self->_compare(@high_pair,@mid_pair) == -1) and ($self->_compare(@low_pair,@mid_pair) == 0) ){
		$end = $mid-1;
		$mid = $low;
		@mid_pair = @low_pair;
	    }elsif( ($self->_compare(@high_pair,@mid_pair) == 0) and ($self->_compare(@low_pair,@mid_pair) == 0) ){
		splice(@hash_sizes, $low+1, $high-$low);
		$end -= ($high-$low);
		$mid = $low;
		@mid_pair = @low_pair;
	    }else{	#low < mid, high < mid
		$start = $low+1;
		$end = $high-1;
	    }			
	}
	$low = POSIX::floor(0.5*($start+$mid));
	$high = POSIX::ceil(0.5*($mid+$end));
    }
    return @mid_pair;
}

sub _run_velveth_get_opt_expcov_covcutoff {
    my ($self, $hash_size) = @_;

    print "Try hash size: $hash_size\n"; #needed for test stdout check
    #run velveth
    my $velveth = $self->_version_path . $self->version .'/velveth';
    my $input_file_format = $self->_resolve_input_file_format(); #fasta or fastq
    my $cmd = $velveth.' '.$self->output_dir.' '.$hash_size.' '.$input_file_format.' -shortPaired '.$self->file;

    print "$cmd\n"; #needed for test stdout check .. before actually executing $cmd
    $self->log_event("$cmd\n");

    if (system ("$cmd")) { #return 0 if successful
	$self->error_message("Failed to run velveth with command\n\t$cmd");
	return;
    }

    #get read count and avg read length of input file
    my $genome_length = $self->_resolve_genome_length();
    my ($read_length, $read_count) = $self->_get_input_read_count_and_length();
    #not sure what ck is .. 
    my $ck = $read_count * ( $read_length - $hash_size + 1) / $genome_length;
    
    my @exp_covs = $self->_resolve_exp_covs(); #return blank array if $self->exp_covs not defined

    my $exp_coverage;
    @exp_covs ? $exp_coverage = $exp_covs[ POSIX::floor($#exp_covs/2) ] : $exp_coverage = 0.9 * $ck;
    #TODO - make better variable names
    my @cov_cutoffs = $self->_resolve_cov_cutoffs(); #return blank array if $self->cov_cutoffs is not defined

    my $cov_cutoff;
    @cov_cutoffs ? $cov_cutoff = $cov_cutoffs[ POSIX::floor($#cov_cutoffs/2) ] : $cov_cutoff = 0.1 * $exp_coverage;

    my $n50;                                              #hash_size just gets passed on and not used
    ($n50, $genome_length) = $self->_run_velvetg_get_n50_total($cov_cutoff, $exp_coverage, $hash_size);

    $self->{genome_length} = $genome_length; #<- global in orig code .. need to retain changes in memory

    print "genome length: $genome_length\n"; #needed to pass test stdout check

    $ck = $read_count * ( $read_length - $hash_size + 1) / $genome_length; #genome length changed

    $self->_pick_best_exp_cov($ck, $hash_size);

    #TODO - probably a better way to do this
    my $hbest_exp_coverage = $self->{hbest_exp_coverage};
    my $hbest_coverage_cutoff = $self->{hbest_coverage_cutoff};
    my @hbest_n50_total = @{$self->{hbest_n50_total}};
    
    my @hbest = ($hash_size, $hbest_exp_coverage, $hbest_coverage_cutoff, @hbest_n50_total);
    
    $self->log_event("@hbest\n");

    print "@hbest\n"; #needed to pass test stdout check
    
    my $name_prefix = $self->_resolve_file_prefix_name();
    my $timing_file = $name_prefix.'-timing';
    my $file_LOG = $self->output_dir.'/Log';
    unless (-s $file_LOG) {
	$self->error_message("File Log does not exist");
	return;
    }
    system("cat $file_LOG >> $timing_file"); #TODO error check

    return @hbest_n50_total; 
}

sub _pick_best_exp_cov {
    my ($self, $ck, $hash_size) = @_;

    my @exp_covs = $self->_resolve_exp_covs();
    unless (@exp_covs) { #returned blank array if $self->exp_covs not defined
	@exp_covs = (POSIX::floor(0.8 * $ck) .. POSIX::floor($ck / 0.95));
    }
    
    my $start = 0;
    my $end = $#exp_covs;
    my $mid = POSIX::floor(0.5*($start+$end));
    my $low = POSIX::floor(0.5*($start+$mid));
    my $high = POSIX::ceil(0.5*($mid+$end));

    my @mid_pair = (0,0);
    my @low_pair = (0,0);
    my @high_pair = (0,0);
    
    @mid_pair = $self->_pick_best_cov_cutoff($exp_covs[$mid], $hash_size);

    while ($start < $end) {
	($start == $mid) ? (@low_pair = @mid_pair) : (@low_pair = (0, 0));		#low == mid
	($end == $mid) ? (@high_pair = @mid_pair) : (@high_pair = (0, 0));		#high == mid

	unless ($low_pair[0]) {
	    @low_pair = $self->_pick_best_cov_cutoff($exp_covs[$low], $hash_size);
	}

	if($self->_compare(@low_pair, @mid_pair) == 1) {
	    $end = $mid-1;
	    $mid = $low;
	    @mid_pair = @low_pair;
		}
	else {	# low <= mid
	    unless ($high_pair[0]) {
		@high_pair = $self->_pick_best_cov_cutoff($exp_covs[$high], $hash_size);
	    }
	    if( ($self->_compare(@high_pair,@low_pair) == 1) or
		(($self->_compare(@high_pair,@mid_pair) == 0) and ($self->_compare(@low_pair,@mid_pair) == -1)) ){
		$start = $mid+1;
		$mid = $high;
		@mid_pair = @high_pair;
	    }elsif( ($self->_compare(@high_pair,@mid_pair) == -1) and ($self->_compare(@low_pair,@mid_pair) == 0) ){
		$end = $mid-1;
		$mid = $low;
		@mid_pair = @low_pair;
	    }elsif( ($self->_compare(@high_pair,@mid_pair) == 0) and ($self->_compare(@low_pair,@mid_pair) == 0) ){
		splice(@exp_covs, $low+1, $high-$low);
		$end -= ($high-$low);
		$mid = $low;
		@mid_pair = @low_pair;
	    }else{	#low < mid, high < mid
		$start = $low+1;
		$end = $high-1;
	    }
	}
	$low = POSIX::floor(0.5*($start+$mid));
	$high = POSIX::ceil(0.5*($mid+$end));
    }
    return @mid_pair;	
}

sub _pick_best_cov_cutoff {
    my ($self, $exp_cov, $hash_size) = @_;

    my @cov_cutoffs = $self->_resolve_cov_cutoffs();
    unless (@cov_cutoffs) {
	@cov_cutoffs = (0 .. POSIX::floor(0.3 * $exp_cov));
    }

    my $start = 0;
    my $end = $#cov_cutoffs;
    my $mid = POSIX::floor(0.5*($start+$end));
    my $low = POSIX::floor(0.5*($start+$mid));
    my $high = POSIX::ceil(0.5*($mid+$end));
    my @mid_pair = (0,0);
    my @low_pair = (0,0);
    my @high_pair = (0,0);

    if (@cov_cutoffs > $self->bound_enumeration) {
	@mid_pair = $self->_run_velvetg_get_n50_total($cov_cutoffs[$mid], $exp_cov, $hash_size);
	while ($start < $end) {
	    ($start == $mid) ? (@low_pair = @mid_pair) : (@low_pair = (0, 0));	#low == mid
	    ($end == $mid) ? (@high_pair = @mid_pair) : (@high_pair = (0, 0));	#high == mid
	    unless ($low_pair[0]) {
		@low_pair = $self->_run_velvetg_get_n50_total($cov_cutoffs[$low], $exp_cov, $hash_size);
	    }
	    if ($self->_compare (@low_pair,@mid_pair) == 1) {
		$end = $mid-1;
		$mid = $low;
		@mid_pair = @low_pair;
	    }
	    else {
		unless ($high_pair[0]) {
		    @high_pair = $self->_run_velvetg_get_n50_total($cov_cutoffs[$high], $exp_cov, $hash_size);
		}
		if( ($self->_compare(@high_pair, @mid_pair) == 1) or (($self->_compare(@high_pair,@mid_pair) == 0) and ($self->_compare(@low_pair,@mid_pair) == -1)) ){
		    $start = $mid+1;
		    $mid = $high;
		    @mid_pair = @high_pair;
		}elsif( ($self->_compare(@high_pair,@mid_pair) == -1) and ($self->_compare(@low_pair,@mid_pair) == 0) ){
		    $end = $mid-1;
		    $mid = $low;
		    @mid_pair = @low_pair;
		}elsif( ($self->_compare(@high_pair,@mid_pair) == 0) and ($self->_compare(@low_pair,@mid_pair) == 0) ){
		    POSIX::splice(@cov_cutoffs, $low+1, $high-$low);  #TODO need to fix ??
		    $end -= ($high-$low);
		    $mid = $low;
		    @mid_pair = @low_pair;
		}else{	#low < mid, high < mid
		    $start = $low+1;
		    $end = $high-1;
		}
	    }
	    $low = POSIX::floor(0.5*($start+$mid));
	    $high = POSIX::ceil(0.5*($mid+$end)); 
	}
    }
    else {
	foreach my $cov_cutoff (@cov_cutoffs){
	    @low_pair = $self->_run_velvetg_get_n50_total($cov_cutoff, $exp_cov, $hash_size);
	    if($self->_compare(@low_pair, @mid_pair) == 1){
		@mid_pair = @low_pair;
	    }
	}
    }
    return @mid_pair;
}

sub _run_velvetg_get_n50_total {
    my ($self, $coverage_cutoff, $exp_coverage, $hash_size) = @_;

    my $velvetg = $self->_version_path . $self->version . '/velvetg';

    my $ins_length_sd = $self->_resolve_ins_length_sd();

    my $screen_g_file = $self->output_dir.'/screen_g'; #capture velvetg output

    my $cmd = $velvetg.' '.$self->output_dir.' -exp_cov '.$exp_coverage.' -cov_cutoff '.$coverage_cutoff.' -ins_length '.$self->ins_length.' -ins_length_sd '.$ins_length_sd;

    print "$cmd\n"; #needed to pass test stdout check

    if (system("$cmd > $screen_g_file")) { #returns 0 if successful
	$self->error_message("Failed to run velvetg with command\n\t$cmd");
	return;
    }

    $self->log_event("$cmd\n");

    #get value from screen_g output file
    my $line = `tail -1 $screen_g_file`;

    unless ($line =~ /n50\s+of\s+(\d+).*total\s+(\d+)/) {
	$self->error_message("Failed to extract n50 and total from $screen_g_file last line\n\t$line");
	return;
    }

    my @n50_total = ($1, $2);
    $self->log_event("@n50_total\n");

    print "@n50_total\n"; #needed to pass test stdout check

    my @best_n50_total = ( defined @{$self->{best_n50_total}} ) ? @{$self->{best_n50_total}} : (0, 0);

    if ($self->_compare(@n50_total, @best_n50_total) == 1) {

	#store best values
	@{$self->{best_n50_total}} = @n50_total;
	$self->{best_exp_coverage} = $exp_coverage;
	$self->{best_coverage_cutoff} = $coverage_cutoff;
	$self->{best_hash_size} = $hash_size;

	#make a copy of contigs.fa file
	my $file_prefix = $self->_resolve_file_prefix_name();
	my $fa_file = $self->output_dir.'/contigs.fa';
	unless (-s $fa_file) {
	    $self->error_message("contigs.fa does not exist to rename");
	    return;
	}
	unless (File::Copy::copy($fa_file, $file_prefix.'-contigs.fa')) {
	    $self->error_message("Failed to copy $fa_file to $file_prefix".'-contigs.fa');
	    return;
	}
    }

    my @hbest_n50_total = ( defined @{$self->{hbest_n50_total}} ) ? @{$self->{hbest_n50_total}} : (0, 0);

    if ($self->_compare(@n50_total, @hbest_n50_total) == 1) {

	#store best values
	@{$self->{hbest_n50_total}} = @n50_total;
	$self->{hbest_exp_coverage} = $exp_coverage;
	$self->{hbest_coverage_cutoff} = $coverage_cutoff;

	#rename contigs.fa file
	my $fa_file = $self->output_dir.'/contigs.fa';
	my $file_prefix = $self->_resolve_file_prefix_name();
	my $new_file_name = $file_prefix.'-hash_size_'.$hash_size.'-contigs.fa';
	rename $fa_file, $new_file_name;
    }
    return @n50_total;
}

sub _compare {
    my ($self, $n1, $t1, $n2, $t2, $from) = @_;

    unless (scalar @_ == 5) {
	$self->error_message("_compare method requires 4 numerical values");
	return;
    }

    #genome length
    my $gl = $self->_resolve_genome_length();

    if (($t1 < 0.95 * $gl or $gl < 0.95 * $t1) and ($t2 < 0.95 * $gl or $gl < 0.95 * $t2)) {
	return 0; # both wrong length
    }
    elsif ($t1 < 0.95 * $gl or $gl < 0.95 * $t1) {
	return -1; # t1 is wrong
    }
    elsif ($t2 < 0.95 * $gl or $gl < 0.95 * $t2) {
	return 1; # t2 is wrong
    }
    elsif ($n1 > $n2) {
	return 1; # n1 is better
    }
    elsif ($n1 < $n2) {
	return -1; # n2 is better
    }
    else {
	return 0; # n1 == n2
    }
    return;
}

sub _print_params_to_screen_and_logfile {
    my $self = shift;

    my $params = "#Your parameters:\n";

    my @hash_sizes = $self->_resolve_hash_sizes();
    $params .= "#hash_sizes: @hash_sizes\n";

    my @exp_covs = $self->_resolve_exp_covs();
    $params .= "#exp_covs: @exp_covs\n";

    my @cov_cutoffs = $self->_resolve_cov_cutoffs();
    $params .= "#cov_cutoffs: @cov_cutoffs\n";

    my $genome_length = $self->_resolve_genome_length();
    $params .= "#genome length: $genome_length\n";

    $params .= "#ins_length: ".$self->ins_length."\n";
    $params .= "#ins_length_sd: ".$self->_resolve_ins_length_sd()."\n";

    $params .= "#input file: ".$self->file."\n";
    $params .= "#output directory: ".$self->output_dir."\n";

    $params .= "#enumeration_bound: ".$self->bound_enumeration."\n";
    $params .= "#version: ".$self->_version_path.$self->version."\n";

    $self->log_event("$params");


    #print needed to pass stdout test -- should remove this from test

    my $txt = `date`."Your parameters:\n" . "hash sizes = @hash_sizes\n";

    $txt .= "exp_covs = @exp_covs\n" if $self->exp_covs;
    $txt .= "cov_cutoffs = @cov_cutoffs\n" if $self->cov_cutoffs;
    #note this will be different than $self->genome_len value
    $txt .= "genome length = $genome_length\n" if $self->genome_len;

    $txt .= "ins_length = ".$self->ins_length."\n".
	    "ins_length_sd = ".$self->_resolve_ins_length_sd()."\n".
	    "input file = ".$self->file."\n".
	    "output directory = ".$self->output_dir."\n".
	    "enumeration bound = ".$self->bound_enumeration."\n";
    
    $txt .= "version = ".$self->_version_path . $self->version."\n" if $self->version;

    print "$txt";

    return 1;
}



sub _resolve_genome_length {
    my $self = shift;
    #global .. changes during execution of code
    return $self->{genome_length} if exists $self->{genome_length};
    #return default or user input value
    return $self->genome_len;
}

sub _version_path {
    return '/gsc/pkg/bio/velvet/velvet_0.7.';
}

sub _resolve_ins_length_sd {
    my $self = shift;

    return $self->dev_ins_length if $self->dev_ins_length;

    return $self->ins_length * 0.2;
}

sub _resolve_exp_covs {
    my $self = shift;

    my @exp_covs;

    if ($self->exp_covs) {
	@exp_covs = $self->exp_covs;
	return sort {$a <=> $b} @exp_covs;
    }
    
    return @exp_covs;
}

sub _resolve_cov_cutoffs {
    my $self = shift;

    my @cov_cutoffs;

    if ($self->cov_cutoffs) {
	@cov_cutoffs = $self->cov_cutoffs;
	return sort {$a <=> $b} @cov_cutoffs;
    }

    return @cov_cutoffs;
}

sub _resolve_hash_sizes {
    my $self = shift;

    return (25, 27, 29) unless $self->hash_sizes;

    my @hash_sizes = $self->hash_sizes;

    return sort {$a <=> $b} @hash_sizes;
}

sub _resolve_input_file_format {
    my $self = shift;

    #this method gets called may times to get same value
    return $self->{input_file_type} if $self->{input_file_type};

    unless (-s $self->file) {
	$self->error_message("Failed to find file ".$self->file);
	return;
    }
    my $input_file = $self->file;

    #TODO - make -file_type command line option?
    my $fh = IO::File->new("< $input_file") ||
	die "Can not open $input_file\n";
    while (my $line = $fh->getline) {
	if ($line =~ /^\>/) {
	    $self->{input_file_type} = '-fasta';
	    return '-fasta';
	} elsif ($line =~ /^\@/) {
	    $self->{input_file_type} = '-fastq';
	    return '-fastq';
	} else {
	    $self->error_message("Can not determine input file type: fasta or fastq");
	    return;
	}
    }

    $fh->close;

    return;
}

sub _get_input_read_count_and_length {
    my $self = shift;

    #this method gets called many times to get same value
    if ($self->{input_read_count} and $self->{avg_read_length}) {
	return $self->{avg_read_length}, $self->{input_read_count};
    }

    unless (-s $self->file) {
	$self->error_message("Failed to find file ".$self->file);
	return;
    }

    #determine read count and total read lengths
    my $read_count = 0;
    my $total_read_length = 0;

    #fasta or fastq
    my $file_format = $self->_resolve_input_file_format();
        
    #TODO can't use bio seqio bec fasta and qual lengths don't seem to match

    #my $io = Bio::SeqIO->new(-format => $file_type, -file => $self->file);
    #while (my $read = $io->next_seq) {
	#$read_count++;
	#$total_read_length += length $read->seq;
    #}

    my $data_fullname = $self->file;
    #TODO -copied from original code .. need to improve
    open (IN, $data_fullname) or die ("Bad file $data_fullname\n");
    my $line = <IN>;

    if($file_format =~ /fasta/){
	$read_count++;
	while(<IN>) {
	    if(/^\>/){
		$read_count++
	    }
	    else{
		$total_read_length += length()-1;
	    }
	}#while
    }#fasta
    elsif($file_format =~ /fastq/){
	while($line) {
	    unless($line =~ /^\@/) {
		exit("Error: more than one line in a single read.");
	    }
	    $read_count++;
	    $line = <IN>;
	    $total_read_length += length($line)-1;
	    for my $i (0..2) {$line = <IN>;}   #Escape 2 lines
	}
    }
    close IN;

    my $average_read_length = $total_read_length / $read_count;

    #store
    $self->{input_read_count} = $read_count;
    $self->{avg_read_length} = $average_read_length;

    return $average_read_length, $read_count;
}

sub log_event {
    my $self = shift;
    my $txt = shift;
    
    #TODO should consider removing log file at start so it doesn't append to existing content

    my $log_file = $self->_log_file;
    
    my $fh = IO::File->new(">> $log_file") ||
	die "Can not create file handle for log file\n";

    $fh->print("$txt");

    $fh->close;

    return 1; #shouldn't return anything
}

sub _log_file {
    my $self = shift;

#    my $prefix_name = $self->_resolve_file_prefix_name();
#    my $output_dir = $self->_resolve_output_dir();
#    my $data_file_name = File::Basename::basename($self->file);
#    return $output_dir.'/'.$prefix_name.'-'.$data_file_name.'-logfile';

    return $self->_resolve_file_prefix_name.'-logfile';
}

sub _resolve_file_prefix_name {
    my $self = shift;

    #called multiple times but want consistant name
    return $self->{files_prefix_name} if exists $self->{files_prefix_name};

    #print DateTime->now."\n";
    #print UR::Time->now."\n";
    #convert Mon May 17 13:53:47 CDT 2010 to Mon-May-17-1353-2010 as part of log file name

    #use date for part of the name
    my $date = `date`;
    chomp $date;
    $date =~ s/\d\d\s+CDT//;
    $date =~ s/\s+/-/g;
    $date =~ s/://g;

    #unless ($date =~  check correct format) { #TODO
	#$self->error_message();
	#return;
    #}

    my $data_file_name = File::Basename::basename($self->file);
    my $file_prefix = $self->output_dir.'/'.$date.'-'.$data_file_name;
    $self->{files_prefix_name} = $file_prefix;

    return $file_prefix;
}


#TODO this is mandidatory here but optional in original code .. maybe need to change later
sub _resolve_output_dir {
    my $self = shift;

    if ($self->output_dir) {
	unless (-d $self->output_dir) {
	    $self->error_message("Invalid directory ".$self->output_dir);
	    return;
	}
	return $self->output_dir;
    }
    #TODO - might have to be careful with this .. if dir changes we don't want it to return `pwd`
    return `pwd`;
}

1;
