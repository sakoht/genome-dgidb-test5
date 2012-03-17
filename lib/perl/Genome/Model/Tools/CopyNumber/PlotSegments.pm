package Genome::Model::Tools::CopyNumber::PlotSegments;

##############################################################################
#
#
#	AUTHOR:		Chris Miller (cmiller@genome.wustl.edu)
#
#	CREATED:	05/05/2011 by CAM.
#
#	NOTES:
#
##############################################################################

use strict;
use Genome;
use IO::File;
use Statistics::R;
use File::Basename;
use warnings;
require Genome::Sys;
use FileHandle;

class Genome::Model::Tools::CopyNumber::PlotSegments {
    is => 'Command',
    has => [
	chr => {
	    is => 'String',
	    is_optional => 1,
	    doc => 'If supplied, only that chromosome will be plotted, otherwise produces a whole-genome plot',
	},

	segment_files => {
	    is => 'String',
	    is_optional => 1,
	    doc => 'comma-seperated list of files containing the segments to be plotted. Expects CBS output - columns: chr, start, stop, #bins, copyNumber (unless the --cnahmm_input or --cnvhmm_input flags are set, in which case it will take the output of cnvHMM/cnaHMM directly',
	},
        tumor_segment_file => {
            is => 'String',
            is_optional => 1,
            is_input => 1,
            doc => 'Tumor segment file, specify tumor and normal segment files or use the segment_files param',
        },
        normal_segment_file => {
            is => 'String',
            is_optional => 1,
            is_input => 1,
            doc => 'Normal segment file, specify tumor and normal segment files or use the segment_files param',
        },
       
        plot_title => {
            is => 'String',
            is_optional => 1,
            is_input => 1,
            doc => 'plot title (also accepts csv list if multiple segment files are specified)',
        },

	gain_threshold => {
	    is => 'Float',
	    is_optional => 1,
	    doc => 'CN threshold for coloring a segment as a gain - defaults to 2.5 or the log2/10 equivalent',
	},

	loss_threshold => {
	    is => 'Float',
	    is_optional => 1,
	    doc => 'CN threshold for coloring a segment as a loss - defaults to 1.5 or the log2/10 equivalent',
	},

	# male_sex_loss_threshold => {
	#     is => 'Float',
	#     is_optional => 0,
	#     doc => 'Threshold for coloring X/Y in males as a gain',
	#     default => 1.5,
	# },

	# male_sex_gain_threshold => {
	#     is => 'Float',
	#     is_optional => 0,
	#     doc => 'Threshold for coloring X/Y in males as a loss',
	#     default => 0.5,
	# },


	log2_input => {
	    is => 'Boolean',
	    is_optional => 1,
	    doc => 'Set this flag if input copy numbers are expressed as log2-ratios, as opposed to absolute copy number',
	},

	log2_plot => {
	    is => 'Boolean',
	    is_optional => 1,
	    doc => 'Set this flag if you want a log2-scaled plot, as opposed to absolute copy number',
	},

        log10_plot => {
            is => 'Boolean',
            is_optional => 1,
	    doc => 'Set this flag if you want a log10-scaled plot, as opposed to absolute copy number',
        },

	highlights => {
	    is => 'String',
	    is_optional => 1,
	    doc => 'file containing regions to highlight, in bed format',
	},

	annotations_top => {
	    is => 'String',
	    is_optional => 1,
	    doc => 'file containing regions to label at the top of the graph. File is in bed format with 4th column (name) used label text. The 5th column (score) can be used to adjust annotations up and down to prevent overlap. For example, -4 moves a label down 4 y-axis units',
	},

	annotations_bottom => {
	    is => 'String',
	    is_optional => 1,
	    doc => 'file containing regions to label at the bottom of the graph. File is in bed format with 4th column (name) used label text. The 5th column (score) can be used to adjust annotations up and down to prevent overlap. For example, 4 moves a label up 4 y-axis units',
	},


	lowres => {
	    is => 'Boolean',
	    is_optional => 1,
            is_input => 1,
	    doc => 'make CN segments appear larger than they actually are for visibility. Without this option, many focal CNs will not be visible on low res plots',
	},

	lowres_min => {
	    is => 'Integer',
	    is_optional => 1,
	    doc => 'if lowres is enabled, segments longer than this many bp (and < lowres_max) will be scaled up to the lowres_max value for visibility',
	    default => '100000'
	},

	lowres_max => {
	    is => 'Integer',
	    is_optional => 1,
	    doc => 'if lowres is enabled, segments shorter than this many bp (and > lowres_min) will be scaled up to the lowres_max value for visibility',
	    default => '5000000'
	},

	ymax => {
	    is => 'Float',
	    is_optional => 1,
            is_input => 1,
	    doc => 'Set the max val of the y-axis',
	},

	ymin => {
	    is => 'Float',
	    is_optional => 1,
	    doc => 'Set the min val of the y-axis',
	},

	xmax => {
	    is => 'Float',
	    is_optional => 1,
            is_input => 1,
	    doc => 'Set the max val of the y-axis',
	},

	xmin => {
	    is => 'Float',
	    is_optional => 1,
	    doc => 'Set the min val of the y-axis',
	},

	hide_normal => {
	    is => 'Boolean',
	    is_optional => 1,
	    doc => 'Plot normal segments in addition to gain and loss',
	    default => 0,
	},

	rcommands_file => {
	    is => 'String',
	    is_optional => 1,
	    doc => 'an output file for your R commands',
	},

	output_pdf => {
	    is => 'String',
	    is_optional => 0,
            is_output => 1,
            is_input => 1,
	    doc => 'pdf file containing your plots',
	},

        genome_build => {
	    is => 'String',
	    is_optional => 1,
            is_input => 1,
	    doc => 'genome build - 36 or 37',
            default => '36',
	},

        sex => {
	    is => 'String',
	    is_optional => 1,
            is_input => 1,
	    doc => 'sex of the sample - male, female, or autosomes',
            default => 'male',
	},

	plot_height => {
	    is => 'Float',
	    is_optional => 1,
	    default => 3,
	    doc => 'height of each plot',
	},

	plot_width => {
	    is => 'Float',
	    is_optional => 1,
	    default => 8,
	    doc => 'width of each plot',
	},

	gain_color => {
	    is => 'String',
	    is_optional => 1,
	    default => "red",
	    doc => 'color of gains/amplifications',
	},

	loss_color => {
	    is => 'String',
	    is_optional => 1,
	    default => "blue",
	    doc => 'color of losses/deletions',
	},

	cnvhmm_input => {
	    is => 'Boolean',
	    is_optional => 1,
            is_input => 1,
	    doc => 'Flag indicating that input is in cnvhmm format, which requires extra parsing',
	    default => 0,
	},

	cnahmm_input => {
	    is => 'Boolean',
	    is_optional => 1,
	    doc => 'Flag indicating that input is in cnahmm format, which requires extra parsing',
	    default => 0,
	},

	baseline => {
	    is => 'Float',
	    is_optional => 1,
	    doc => 'value seperating gains from losses. defaults to 2 for absolute plots or 0 for log plots',
	},

	ylabel => {
	    is => 'String',
            is_optional => 1,
            doc => 'y-axis label',
    },

    label_size => {
	    is => 'Float',
	    is_optional => 1,
            is_input => 1,
	    doc => 'Make the text labels on the plot bigger or smaller',
	    default => 0.6,
	},

    ]
};

sub help_brief {
    "generate a plot of copy number alterations"
}

sub help_detail {
    "generate a plot of copy number alterations.\n\nExample:\ngmt copy-number plot-segments --segment_files copynumber.cn.seg --cnvhmm-input --plot-title AML01 --lowres --output-pdf copynumber.cn.seg.pdf"
}


#########################################################################

#-----------------------------------------------------------
# convert files between formats and write out a new file for
# the R script to read in
sub convertSegs{
    my ($self, $segfiles, $cnvhmm_input, $cnahmm_input) = @_;
    my @newfiles;
    my @infiles = split(",",$segfiles);

    foreach my $file (@infiles){
        if ($cnvhmm_input){
            my $cbsfile = cnvHmmToCbs($file,$self);
            push(@newfiles,$cbsfile);

        } elsif ($cnahmm_input){
            my $cbsfile = cnaHmmToCbs($file,$self);
            push(@newfiles,$cbsfile);
        }
    }
    return join(",",@newfiles);
}


#-----------------------------------------------------------
# convert scores between bases and write out a new file for
# the R script to read in
sub convertScores{
    my ($self, $segfiles, $log2_input, $log2_plot, $log10_plot) = @_;
    my @newfiles;
    my @infiles = split(",",$segfiles);

    foreach my $file (@infiles){
        if ($log2_input && $log10_plot){
            my $cbsfile = scoreConv(2, 10, $file, $self);
            push(@newfiles,$cbsfile);

        } elsif ($log2_input && (!($log2_plot))){
            my $cbsfile = scoreConv(2, "abs", $file, $self);
            push(@newfiles,$cbsfile);

        } elsif (!($log2_input) && $log2_plot){
            my $cbsfile = scoreConv("abs", 2, $file, $self);
            push(@newfiles,$cbsfile);

        } elsif (!($log2_input) && $log10_plot){
            my $cbsfile = scoreConv("abs", 10, $file, $self);
            push(@newfiles,$cbsfile);
        } else {
            return $segfiles;
        }
    }
    return join(",",@newfiles);
}


#-----------------------------------------------------
#take the log with a different base
#(log2 = log_base(2,values)
sub log_base {
    my ($base, $value) = @_;
    $value = 0.000001 if($value == 0);
    return log($value)/log($base);
}


#-----------------------------------------------------
#convert scores from log to abs, vice-versa, or between different bases
sub scoreConv{
    my ($from, $to, $file, $self) = @_;

    #create a tmp file for this output
    my ($tfh,$newfile) = Genome::Sys->create_temp_file;
    unless($tfh) {
	$self->error_message("Unable to create temporary file $!");
	die;
    }
    open(OUTFILE,">$newfile") || die "can't open temp segs file for writing ($newfile)\n";


    #read and convert the output
    my $inFh = IO::File->new( $file ) || die "can't open file\n";
    while( my $line = $inFh->getline )
    {
        next if $line =~/^#/;
        my @fields = split("\t",$line);

        if( ($from eq 2) && ($to eq "abs")){
            print OUTFILE join("\t",($fields[0],$fields[1],$fields[2],$fields[3],((2**$fields[4])*2))) . "\n";
        } elsif( ($from eq 2) && ($to eq 10)){
            print OUTFILE join("\t",($fields[0],$fields[1],$fields[2],$fields[3],$fields[4]/(log_base(2,10)))) . "\n";
        } elsif( ($from eq "abs") && ($to eq 2)){
            print OUTFILE join("\t",($fields[0],$fields[1],$fields[2],$fields[3],log_base(2,$fields[4]/2))) . "\n";
        } elsif( ($from eq "abs") && ($to eq 10)){
            print OUTFILE join("\t",($fields[0],$fields[1],$fields[2],$fields[3],log_base(10,$fields[4]/2))) . "\n";
        }
    }

    close(OUTFILE);
    $inFh->close;
    return($newfile);
}



#-----------------------------------------------------
#convert cnvhmm output to a format we can use here
sub cnvHmmToCbs{
    my ($file,$self) = @_;

    #create a tmp file for this output
    my ($tfh,$newfile) = Genome::Sys->create_temp_file;
    unless($tfh) {
	$self->error_message("Unable to create temporary file $!");
	die;
    }
    open(OUTFILE,">$newfile") || die "can't open temp segs file for writing ($newfile)\n";


    #read and convert the cnvhmm output
    my $inFh = IO::File->new( $file ) || die "can't open file\n";
    my $inCoords = 0;
    while( my $line = $inFh->getline )
    {
	chomp($line);
	if ($line =~ /^#CHR/){
	    $inCoords = 1;
	    next;
	}
	if ($line =~ /^---/){
	    $inCoords = 0;
	    next;
	}

	if ($inCoords){
	    my @fields = split("\t",$line);
	    print OUTFILE join("\t",($fields[0],$fields[1],$fields[2],$fields[4],log_base(2,$fields[6]/2))) . "\n";
	}
    }
    close(OUTFILE);
    $inFh->close;
    return($newfile);
}

#-----------------------------------------------------
#convert cnahmm output to a format we can use here
sub cnaHmmToCbs{
    my ($file,$self) = @_;

    #create a tmp file for this output
    my ($tfh,$newfile) = Genome::Sys->create_temp_file;
    unless($tfh) {
	$self->error_message("Unable to create temporary file $!");
	die;
    }
    open(OUTFILE,">$newfile") || die "can't open temp segs file for writing ($newfile)\n";


    #read and convert the cnvhmm output
    my $inFh = IO::File->new( $file ) || die "can't open file\n";
    my $inCoords = 0;
    while( my $line = $inFh->getline )
    {
	chomp($line);
	if ($line =~ /^#CHR/){
	    $inCoords = 1;
	    next;
	}
	if ($line =~ /^---/){
	    $inCoords = 0;
	    next;
	}

	if ($inCoords){
	    my @fields = split("\t",$line);
	    next if($fields[6] == 0 or $fields[8] ==0); #skip line that would result in dividing by zero or taking log of zero.
	    print OUTFILE join("\t",($fields[0],$fields[1],$fields[2],$fields[4],(log_base(2,$fields[6]/$fields[8])))) . "\n";
	}
    }
    close(OUTFILE);
    $inFh->close;
    return($newfile);
}


#-------------------------------------

sub getEntrypointsFile{
    my ($sex, $genome_build) = @_;
    #set the appropriate entrypoints file so that we know the
    # chrs and lengths
    my $entrypoints_file = "";
    if($sex eq "male"){
        if($genome_build eq "36"){
            $entrypoints_file = "/gscmnt/sata921/info/medseq/cmiller/annotations/entrypoints.hg18.male"
        } elsif ($genome_build eq "37"){
            $entrypoints_file = "/gscmnt/sata921/info/medseq/cmiller/annotations/entrypoints.hg19.male"
    }
    } elsif ($sex eq "female"){
        if($genome_build eq "36"){
            $entrypoints_file = "/gscmnt/sata921/info/medseq/cmiller/annotations/entrypoints.hg18.female"
        } elsif ($genome_build eq "37"){
            $entrypoints_file = "/gscmnt/sata921/info/medseq/cmiller/annotations/entrypoints.hg19.female"
    }
    } elsif ($sex eq "autosomes"){
        if($genome_build eq "36"){
            $entrypoints_file = "/gscmnt/sata921/info/medseq/cmiller/annotations/entrypoints.hg18.autosomes"
        } elsif ($genome_build eq "37"){
            $entrypoints_file = "/gscmnt/sata921/info/medseq/cmiller/annotations/entrypoints.hg19.autosomes"
    }

    }

    if ($entrypoints_file eq ""){
        die "Specify a valid genome build and sex. Only genome builds 36/37 and male/female are currently supported";
    }

    return $entrypoints_file;
}

sub execute {
    my $self = shift;
    my $chr = $self->chr;
    my $segment_files = $self->segment_files;
    my $gain_threshold = $self->gain_threshold;
    my $loss_threshold = $self->loss_threshold;
    my $log2_input = $self->log2_input;
    my $log2_plot = $self->log2_plot;
    my $log10_plot = $self->log10_plot;
    my $highlights = $self->highlights;
    my $annotations_top = $self->annotations_top;
    my $annotations_bottom = $self->annotations_bottom;
    my $lowres = $self->lowres;
    my $lowres_min = $self->lowres_min;
    my $lowres_max = $self->lowres_max;
    my $ymax = $self->ymax;
    my $ymin = $self->ymin;
    my $xmax = $self->xmax;
    my $xmin = $self->xmin;
    my $hide_normal = $self->hide_normal;
    my $genome_build = $self->genome_build;
    my $sex = $self->sex;
    my $output_pdf = $self->output_pdf;
    my $rcommands_file = $self->rcommands_file;
    my $plot_height = $self->plot_height;
    my $plot_width = $self->plot_width;
    my $gain_color = $self->gain_color;
    my $loss_color = $self->loss_color;
    my $cnvhmm_input = $self->cnvhmm_input;
    my $baseline = $self->baseline;
    my $cnahmm_input = $self->cnahmm_input;
    my $plot_title = $self->plot_title;
    my $ylabel = $self->ylabel;
    my $tumor_segment_file = $self->tumor_segment_file;
    my $normal_segment_file = $self->normal_segment_file;
    my $label_size = $self->label_size;


    #sanity checks
    unless( (defined($segment_files)) xor (defined($tumor_segment_file) && defined($normal_segment_file))){
        die $self->error_message("You must specify either the segment_files param OR both tumor_segment_file and normal_segment_file, but not all three.");
    }

    if ((defined($xmax) || defined($xmin)) && !(defined($chr))){
        die $self->error_message("xmin and xmax can only be used on individual chromosome views");
    }



    if(defined($tumor_segment_file) && defined($normal_segment_file)){
        $segment_files = join(",",($tumor_segment_file,$normal_segment_file));
    }

    my $entrypoints_file = getEntrypointsFile($sex,$genome_build);


    my @infiles;
    #first do file conversion from cnv/aHMM output if necessary
    if ($cnvhmm_input || $cnahmm_input){
	$segment_files = convertSegs($self, $segment_files, $cnvhmm_input, $cnahmm_input);
        $log2_input = 1;
    }

    #then do score conversion between log2/log10/absolute CN as necessary
    $segment_files = convertScores($self, $segment_files, $log2_input, $log2_plot, $log10_plot);
  
    @infiles = split(",",$segment_files);

    #set up a temp file for the R commands (unless one is specified)
    my $temp_path;
    my $tfh;
    my $outfile = "";

    if (defined($rcommands_file)){
	$outfile = $rcommands_file;
    } else {
    	my ($tfh,$tfile) = Genome::Sys->create_temp_file;
    	unless($tfh) {
    	    $self->error_message("Unable to create temporary file $!");
    	    die;
    	}
	$outfile=$tfile;
    }


    #preset some params for the different plot styles

    unless(defined($gain_threshold)){
        $gain_threshold = 2.5;
        if ($log2_plot){
            $gain_threshold = log_base(2,$gain_threshold/2);
        } elsif ($log10_plot){
            $gain_threshold = log_base(10,$gain_threshold/2);
        }
    }
    unless(defined($loss_threshold)){
        $loss_threshold = 1.5;
        if ($log2_plot){
            $loss_threshold = log_base(2,$loss_threshold/2);
        } elsif ($log10_plot){
            $loss_threshold = log_base(10,$loss_threshold/2);
        }
    }

    unless(defined($baseline)){
        if ($log2_plot){
            $baseline = 0;
        } elsif ($log10_plot){
            $baseline = 0;
        } else {
            $baseline = 2;
        }
    }

    unless(defined($ymin)){
        unless($log2_plot || $log10_plot){
            $ymin = -2;
        }
    }


    #open the R file
    open(R_COMMANDS,">$outfile") || die "can't open $outfile for writing\n";

    #source the R file
    my $dir_name = dirname(__FILE__);
    print R_COMMANDS "source(\"" . $dir_name . "/PlotSegments.R\")\n";


    #set up pdf parameters
    my $docwidth = $plot_width;
    my $docheight = $plot_height * @infiles;
    print R_COMMANDS "pdf(file=\"" . $output_pdf . "\",width=" .$docwidth .",height=" . $docheight . ")\n";


    #set up the plotting space
    if(defined($chr) && defined($plot_title)){
        print R_COMMANDS "par(xaxs=\"i\", xpd=FALSE, mfrow=c(" . @infiles . ",1), oma=c(1,1,1,1), mar=c(3,3,1,1))\n";
    } else {
        print R_COMMANDS "par(xaxs=\"i\", xpd=FALSE, mfrow=c(" . @infiles . ",1), oma=c(1,1,1,1), mar=c(1,3,1,1))\n";
    }

    #set up the titles
    my @titles;
    if(defined($plot_title)){
        @titles = split(",",$plot_title);
    }
    my $counter = 0;


    #draw the plots for each set of segments
    foreach my $infile (@infiles){
        
        #sanity check - the infile exists and is not empty
        unless (-s $infile){
            die("input file contains no segments to plot");
        }

	print R_COMMANDS "plotSegments(";

	#first the core stuff
	if(defined($chr)){
	    print R_COMMANDS 'chr="' . $chr . '"';
	} else {
	    print R_COMMANDS "chr=\"ALL\"";
	}
	print R_COMMANDS ", filename=\"" . $infile . "\"";
	print R_COMMANDS ", entrypoints=\"" . $entrypoints_file . "\"";

	#then the optional parameters
	if(defined($ymax)){
	    print R_COMMANDS ", ymax=" . $ymax;
	}

    if(defined($ymin)){
	    print R_COMMANDS ", ymin=" . $ymin;
        }

	if(defined($xmax)){
	    print R_COMMANDS ", xmax=" . $xmax;
	}

    if(defined($xmin)){
	    print R_COMMANDS ", xmin=" . $xmin;
        }

	if (defined($highlights)){
	    print R_COMMANDS ", highlights=\"" . $highlights . "\"";
	}

	if (defined($annotations_top)){
	    print R_COMMANDS ", annotationsTop=\"" . $annotations_top . "\"";
	}

	if (defined($annotations_bottom)){
	    print R_COMMANDS ", annotationsBottom=\"" . $annotations_bottom . "\"";
	}

	if ($lowres){
	    print R_COMMANDS ", lowRes=TRUE";
	}

	if (defined($lowres_min)){
	    print R_COMMANDS ", lowResMin=" . $lowres_min;
	}

	if (defined($lowres_max)){
	    print R_COMMANDS ", lowResMax=" . $lowres_max;
	}

	if (defined($label_size)){
	    print R_COMMANDS ", label_size=" . $label_size;
	}

	if ($hide_normal){
	    print R_COMMANDS ", showNorm=FALSE";
	} else {
	    print R_COMMANDS ", showNorm=TRUE";
	}

	print R_COMMANDS ", gainThresh=" . $gain_threshold;
	print R_COMMANDS ", lossThresh=" . $loss_threshold;

	print R_COMMANDS ", gainColor=\"" . $gain_color . "\"";
	print R_COMMANDS ", lossColor=\"" . $loss_color . "\"";

        if(defined($baseline)){
            print R_COMMANDS ", baseline=\"" . $baseline . "\"";
        }

	if (defined($plot_title)){
	    print R_COMMANDS ", plotTitle=\"" . $titles[$counter] . "\"";
	}

	if (defined($ylabel)){
            print R_COMMANDS ", ylabel=\"" . $ylabel . "\"";
        } else {
            if($log2_plot){
	 	print R_COMMANDS ", ylabel=\"Log2 Copy Number\"";
            } elsif($log10_plot){
	 	print R_COMMANDS ", ylabel=\"Log10 Copy Number\"";
            } else {
	 	print R_COMMANDS ", ylabel=\"Copy Number\"";
            }
        }

	print R_COMMANDS ")\n";
        $counter++;
    }

    #close the file out
    print R_COMMANDS "dev.off()\n";
    print R_COMMANDS "q()\n";
    close R_COMMANDS;

    #now run the R command
    my $cmd = "R --vanilla --slave \< $outfile";
    my $return = Genome::Sys->shellcmd(
	cmd => "$cmd",
        );
    unless($return) {
	$self->error_message("Failed to execute: Returned $return");
	die $self->error_message;
    }
    return $return;
}

1;
