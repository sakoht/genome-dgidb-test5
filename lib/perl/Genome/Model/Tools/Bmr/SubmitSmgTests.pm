package Genome::Model::Tools::Bmr::SubmitSmgTests;

use strict;
use warnings;

use Genome;
use IO::File;
use Time::HiRes qw(sleep); #This alternate sleep() allows delays that are fractions of a second

class Genome::Model::Tools::Bmr::SubmitSmgTests
{
  is => 'Genome::Command::Base',
  has_input => [
  working_dir => {
    is => 'String',
    is_optional => 0,
    doc => 'Directory where the submitted jobs can write their results and stdout',
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
This script runs the SMG test on each gene_summary file generated after running
SubmitBatchGeneSummary.pm. The results are stored in a new directory called smg_test_results.
HELP
}

sub execute
{
  my $self = shift;
  my $work_dir = $self->working_dir;
  $work_dir =~ s/\/$//;
  my $bmr_dir = $work_dir . "/gene_summary_results";
  my $output_dir = $work_dir . "/smg_test_results";
  my $stdout_dir = $work_dir . "/smg_test_stdout";
  my $class_summary = $work_dir . "/combined.class_summary";
  mkdir $output_dir unless -d $output_dir;
  mkdir $stdout_dir unless -d $stdout_dir;

  #Grab classes of variants and BMRs from the combined class_summary file
  my $classSumFh = IO::File->new( $class_summary );
  my %BMR = ();
  $classSumFh->getline; #Discard the header
  while( my $line = $classSumFh->getline )
  {
    my ( $class, $bmr, $cov, $muts ) = split( /\t/, $line );
    $BMR{$class} = $bmr;
  }
  $classSumFh->close;

  opendir( BMR_DIR, $bmr_dir ) or die "Cannot open directory $bmr_dir $!";
  my @files = readdir( BMR_DIR );
  closedir( BMR_DIR );
  @files = grep { /\.gene_summary$/ } @files;
  @files = map { "$bmr_dir/" . $_ } @files;

  #Update the BMR for each gene_summary file, in case they were recalculated
  foreach my $gene_summary_file ( @files )
  {
    my $fileBuff = '';
    my $sameBmr = 1;
    my $fh = IO::File->new( $gene_summary_file );
    $fileBuff = $fh->getline; #Buffer up the header as is
    while( my $line = $fh->getline )
    {
      chomp( $line );
      my ( $gene, $class, $cov, $muts, $bmr ) = split( /\t/, $line );
      $sameBmr = 0 if( $bmr ne $BMR{$class} );
      $fileBuff .= join( "\t", $gene, $class, $cov, $muts, $BMR{$class} ) . "\n";
    }
    $fh->close;
    #If the BMR is unchanged, we don't need to be doing this
    last if( $sameBmr );
    #Overwrite the existing file with the new BMR values
    my $overwriteFh = IO::File->new( $gene_summary_file, ">" );
    $overwriteFh->print( $fileBuff );
    $overwriteFh->close;
  }

  my $submitCnt = 0;
  foreach my $gene_summary_file ( @files )
  {
    my ( $piece ) = $gene_summary_file =~ m/(\d+)\.gene_summary$/;
    my $jobname = "smgtest-" . $piece;
    my $outfile = "$output_dir/" . $piece . ".pvalues";
    my $stdout_file = "$stdout_dir/" . $piece . ".stdout";
    sleep(0.2); #Pause for a short while to avoid overloading LDAP, and to help out the disks
    print `bsub -q tcga -M 4000000 -R 'select[type==LINUX64 && mem>4000] rusage[mem=4000]' -oo $stdout_file -J $jobname gmt bmr smg-test --gene-summary $gene_summary_file --output-file $outfile`;
    ++$submitCnt;
  }

  return 1;
}

1;
