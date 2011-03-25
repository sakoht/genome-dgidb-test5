package Genome::Model::Tools::Bmr::SubmitGeneSummary;

use strict;
use warnings;

use Genome;
use IO::File;
use Time::HiRes qw(sleep); #This alternate sleep() allows delays that are fractions of a second

class Genome::Model::Tools::Bmr::SubmitGeneSummary
{
    is => 'Genome::Command::Base',
    has_input => [
    roi_bedfile => {
        type => 'String',
        is_optional => 0,
        doc => 'BED file used to limit background regions of interest when calculating BMR',
    },
    max_job_count => {
        type => 'Integer',
        is_optional => 0,
        doc => 'Number of jobs to run in parallel. Actual number could be fewer depending on how the bedfile can be split',
    },
    maf_file => {
        type => 'String',
        is_optional => 0,
        doc => 'List of mutations used to calculate background mutation rate',
    },
    working_dir => {
        is => 'String',
        is_optional => 0,
        doc => 'Directory where the submitted jobs can write their results and stdout',
    },
    wiggle_file_dirs => {
        type => 'Csv',
        is_optional => 0,
        doc => 'Directories containing wiggle files for each sample (comma-delimited)',
    },
    class_summary_file => {
        type => 'String',
        is_optional => 0,
        doc => 'File containing BMRs calculated using \'gmt bmr class-summary\'',
    },
    ]
};

sub help_brief
{
    "Submits batch-gene-summary jobs to run in parallel"
}

sub help_detail
{
    return <<HELP;
This script splits the given BED file containing regions of interest into smaller pieces and then
submits a batch-gene-summary job for each piece in order to take advantage of parallelism. But
each job running in parallel will each need to load 316 wiggle files. So there is an advantage to
running fewer jobs in parallel. And the number of pieces to create from the given ROI BED file is
user configurable. So choose it wisely!
HELP
}

sub execute
{
    my $self = shift;
    my $bedfile = $self->roi_bedfile;
    my $max_job_count = $self->max_job_count;
    my $maf_file = $self->maf_file;
    my $class_summary = $self->class_summary_file;
    my $wiggle_dirs = '"' . $self->wiggle_file_dirs . '"';

    #Count the number of lines in the bedfile to give us an idea of how to split it
    my $bed_lines = `wc -l < $bedfile`;
    die "wc failed: $?" if $?;
    chomp($bed_lines);
    if( $max_job_count > $bed_lines )
    {
        $self->error_message("Too few lines in the bedfile to split it as requested");
        return;
    }
    my $min_lines_per_piece = int( $bed_lines / $max_job_count );

    #Break the bedfile into pieces and store them in a directory at the same location
    mkdir "$bedfile\_pieces" unless -d "$bedfile\_pieces";
    my $bedfh = IO::File->new( $bedfile );
    my ( $linecount, $filecount ) = ( 0, 1 );
    my $previous_gene = '';
    my @bed_pieces = ();
    my $outfile = "$bedfile\_pieces/" . 'roi_bed.part' . $filecount;
    push( @bed_pieces, $outfile );
    my $outfh = IO::File->new( $outfile, ">" );
    while (my $line = $bedfh->getline)
    {
        $linecount++;
        chomp $line;
        my ( $chr, $start, $stop, $exon_id ) = split( /\t/, $line );
        if( $chr eq "M" ) { $chr = "MT"; } #for broad roi lists
        my ( $gene ) = $exon_id =~ m/(^[^\.]+)\.*.*/;
        my $newline = join( "\t", $chr, $start, $stop, $gene ) . "\n";
        #If it's time to start a new file
        if( $linecount > $min_lines_per_piece && $gene ne $previous_gene )
        {
            $outfh->close;
            $filecount++;
            $outfile = "$bedfile\_pieces/" . 'roi_bed.part' . $filecount;
            push( @bed_pieces, $outfile );
            $outfh = IO::File->new( $outfile, ">" );
            $linecount = 1;
        }
        print $outfh $newline;
        $previous_gene = $gene;
    }
    $outfh->close;
    $bedfh->close;

    #Create directories for storing output and stdout generated by the jobs
    my $output_dir = $self->working_dir;
    $output_dir =~ s/\/$//;
    $output_dir = $output_dir . "/gene_summary_results/";
    mkdir $output_dir unless -d $output_dir;
    my $stdout_dir = $self->working_dir;
    $stdout_dir =~ s/\/$//;
    $stdout_dir = $stdout_dir . "/gene_summary_stdout/";
    mkdir $stdout_dir unless -d $stdout_dir;

    my $submitCnt = 0;
    foreach my $roi_file( @bed_pieces )
    {
        ++$submitCnt;
        #Insert a longer delay between every few jobs to avoid thrashing the drives
        #sleep(1) if ($submitCnt % 10 == 0);
        my ( $piece ) = $roi_file =~ m/part(\d+)$/;
        my $jobname = "genesum-" . $piece;
        my $outfile = $output_dir . $piece . ".gene_summary";
        my $stdout_file = $stdout_dir . $piece . ".stdout";
        sleep(0.1); #Pause for a short while to avoid overloading LDAP, and to help out the disks
        print `bsub -M 3000000 -R 'select[localdata && mem>3000] rusage[mem=3000]' -oo $stdout_file -J $jobname gmt bmr gene-summary --mutation-maf-file $maf_file --output-file $outfile --roi-bedfile $roi_file --wiggle-file-dirs $wiggle_dirs --class-summary-file $class_summary`;
    }

    return 1;
}

1;
