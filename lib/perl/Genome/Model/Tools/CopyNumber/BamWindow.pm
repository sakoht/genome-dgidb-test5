package Genome::Model::Tools::CopyNumber::BamWindow;

##############################################################################
#
#
#	AUTHOR:		Chris Miller (cmiller@genome.wustl.edu)
#	CREATED:	11/30/2011 by CAM.
#	NOTES:
#
##############################################################################

use strict;
use Genome;
use IO::File;
use warnings;
use Digest::MD5 qw(md5_hex);
use FileHandle;

class Genome::Model::Tools::CopyNumber::BamWindow {
    is => 'Command',
    has => [
	bam_file => {
	    is => 'String',
	    is_optional => 0,
	    doc => 'bam file to count tumor reads from',
	},
        
        per_lib => {
	    is => 'String',
	    is_optional => 1,
            default => 1,
	    doc => 'do counts on a per-library basis',
	},
        
	output_file => {
	    is => 'String',
	    is_optional => 0,
	    doc => 'output file',
	},
        
        minimum_mapping_quality => {
	    is => 'Integer',
	    is_optional => 1,
	    doc => 'minimum mapping quality required for a read to be included',
            default => 20,
	},
        
        extra_params => {
            is => 'String',
            is_optional => 1,
            doc => 'extra parameters to pass to bam-window',
            default => "-s",
        },

        lib_as_readgroup => {
            is => 'Boolean',
            is_optional => 1,
            doc => 'some bams don\'t have readgroups and libraries listed in the header, and instead use the library name as the readgroup name in the bam. In this case, we can extract these from the bam lines and use them, at the cost of having to rad through the bam file twice',
            default => 0,
        },

        window_size => {
            is => 'Integer',
	    is_optional => 1,
	    doc => 'size of the bins to count reads in',
            default => 10000,
        },

        ]
};

sub help_brief {
    "Wrapper around bam-window, includes per-lib preprocessing"
}

sub help_detail {
    "Wrapper around bam-window, includes per-lib preprocessing"
}

#########################################################################

sub execute {
    my $self = shift;
    my $temp_output_file;


    if($self->per_lib){
        #create a temp file
        $temp_output_file = Genome::Sys->create_temp_file_path;
        my $ofh = Genome::Sys->open_file_for_writing($temp_output_file);
        unless($ofh) {
            $self->error_message("Unable to open temp file for writing.");
            die;
        }

        #now get the libraries, associated readgroups, and md5hashes of the lib name      
  
        if(!($self->lib_as_readgroup)){        
            #simple way - get them from the header            
            my $cmd="samtools view -H " . $self->bam_file;       
            open(HEADER, "$cmd |") || die "can't open file $ARGV[0]\n";
            my $count = 0;
            while(<HEADER>)
            {
                next unless $_ =~ /^\@RG/;
                chomp($_);
                my @F = split("\t",$_);
                if ($F[4] =~ /LB:(.+)/){
                    my $lib = $1;
                    if ($F[1] =~ /ID:(.+)/){
                        print $ofh $lib . "\t" . $1 . "\t" . md5_hex($1) . "\n";
                        $count++;
                    }
                }            
            }
            if($count == 0){
                die("no readgroups in the header, can't do per-library counts\nIf the libraries are used in place of readgroups in the main file (\"RG:Z:libraryName\"), \ntry the --lib-as-readgroup option\n");
                
            }
        } else {
            #slow way - have to read through the whole bam file and get the readgroups/libs
            my $cmd="samtools view " . $self->bam_file;
            open(HEADER, "$cmd |") || die "can't open file $ARGV[0]\n";
            my $count = 0;
            my %libHash;
            while(<HEADER>)
            {
                if($_ =~ /RG:Z:([^\s]+)\s/){
                    my $lib = $1;
                    unless(exists($libHash{$lib})){
                        print $ofh $lib . "\t" . $lib . "\t" . md5_hex($lib) . "\n";
                        $count++;
                        $libHash{$lib} = 0;
                    }
                }            
            }
            if($count == 0){
                die("no readgroups in the file, can't do per-library counts\n");                
            }                    
        }
    }

    my $a = "cp " . $temp_output_file . " " . $self->output_file . ".libs";
    print STDERR "$a";
    `$a`;

    my $cmd = "~/usr/src/bamwindow-v0.2/bam-window";
    $cmd .= " -q " . $self->minimum_mapping_quality;
    $cmd .= " -w " . $self->window_size;

    if($self->per_lib){
        $cmd .= " -r " . $temp_output_file;
    }

    $cmd .= " " . $self->extra_params;
    $cmd .= " " . $self->bam_file;
    $cmd .= " >" . $self->output_file;

    my $return = Genome::Sys->shellcmd(
	cmd => "$cmd",
        );
    unless($return) {
	$self->error_message("Failed to execute: Returned $return");
	die $self->error_message;
    }
    return $return;
}
