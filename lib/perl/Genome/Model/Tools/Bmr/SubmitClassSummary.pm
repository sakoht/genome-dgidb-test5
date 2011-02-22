package Genome::Model::Tools::Bmr::SubmitClassSummary;

use warnings;
use strict;

use Genome;
use IO::File;
use Time::HiRes qw(sleep); #This alternate sleep() allows delays that are fractions of a second

class Genome::Model::Tools::Bmr::SubmitClassSummary {
    is => 'Genome::Command::Base',
    has_input => [
    wiggle_file_dirs => {
        is => 'Comma-delimited String',
        is_optional => 0,
        doc => 'Comma-delimited list of directories containing wiggle files',
    },
    maf_file => {
        is => 'String',
        is_optional => 0,
        doc => 'MAF file containing all mutations to be considered in the test',
    },
    roi_bedfile => {
        is => 'String',
        is_optional => 0,
        doc => 'BED file used to limit background regions of interest when calculating BMR',
    },
    working_dir => {
        is => 'String',
        is_optional => 0,
        doc => 'Directory where the submitted jobs can write their results and stdout',
    },
    genes_to_exclude => {
        is => 'Comma-delimited String',
        is_optional => 1,
        doc => 'Comma-delimited list of genes to exclude in the BMR calculation',
    },
    ]
};

sub help_brief {
    "Submits batch-class-summary jobs, 1 per wiggle file."
}

sub help_detail {
    "Submit batch-class-summary jobs, 1 per wiggle file in the given directories. Do not bsub this command."
}

sub execute {
    my $self = shift;

    #Parse wiggle file directories to obtain the path to wiggle files
    my %wiggle_files; # %wiggle_files -> wigfile = full_path_wigfile
    my @wiggle_dirs = split( /,\s*/, $self->wiggle_file_dirs );
    foreach my $wiggle_dir (@wiggle_dirs) {
        $wiggle_dir = (( $wiggle_dir =~ m/\/$/ ) ? $wiggle_dir : "$wiggle_dir/" );
        opendir(WIG_DIR, $wiggle_dir) or die "Cannot open directory $wiggle_dir $!\n";
        my @files = readdir(WIG_DIR);
        closedir(WIG_DIR);
        @files = grep { /\.wig$/ } @files;
        for my $file (@files) {
            my $full_path_file = $wiggle_dir . $file;
            $wiggle_files{$file} = $full_path_file;
        }
    }

    #required inputs
    my $maf = $self->maf_file;
    my $roi_bed = $self->roi_bedfile;

    #Create directories for storing output and stdout generated by the jobs
    my $output_dir = $self->working_dir;
    $output_dir =~ s/\/$//;
    $output_dir = $output_dir . "/class_summary_results/";
    mkdir $output_dir unless -d $output_dir;
    my $stdout_dir = $self->working_dir;
    $stdout_dir =~ s/\/$//;
    $stdout_dir = $stdout_dir . "/class_summary_stdout/";
    mkdir $stdout_dir unless -d $stdout_dir;

    my $genes_to_exclude_arg = $self->genes_to_exclude;
    #Don't use this argument in the bsub below if it wasn't passed to this module
    if(defined $genes_to_exclude_arg) {
        $genes_to_exclude_arg = "--genes-to-exclude \"$genes_to_exclude_arg\"";
    }
    else {
        $genes_to_exclude_arg = '';
    }

    my $submitCnt = 0;
    foreach my $wigfile (keys %wiggle_files) {
        ++$submitCnt;
        #Insert a longer delay between every few jobs to avoid thrashing the drives
        #sleep(1) if ($submitCnt % 10 == 0);
        my $jobname = "classsum-" . $wigfile;
        my $outfile = $output_dir . $wigfile . ".class_summary";
        my $stdout_file = $stdout_dir . $wigfile . ".stdout";
        my $wiggle = $wiggle_files{$wigfile};
        sleep(0.1); #Pause for a short while to avoid overloading LDAP, and for the disk's sake
        print `bsub -M 2500000 -R 'select[localdata && mem>2500] rusage[mem=2500]' -oo $stdout_file -J $jobname gmt bmr class-summary --mutation-maf-file $maf --output-file $outfile --roi-bedfile $roi_bed --wiggle-file $wiggle $genes_to_exclude_arg`;
    }

    return 1;
}

1;
