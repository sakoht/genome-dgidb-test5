#!/usr/bin/perl
#Written by Malachi Griffith and Nate Dees

#Load modules
use strict;
use warnings;
use Genome;
use Getopt::Long;
use Term::ANSIColor qw(:constants);
use Data::Dumper;

my $script_dir;
use Cwd 'abs_path';
BEGIN{
  if (abs_path($0) =~ /(.*\/).*\/.*\.pl/){
    $script_dir = $1;
  }
}
use lib $script_dir;
use ClinSeq qw(:all);


#This script running a series of commands obtained from Nate Dees that results in the creation of a clonality plot (.pdf)
my $somatic_var_model_id = '';
my $working_dir = '';
my $common_name = '';
my $verbose = 0;

GetOptions ('somatic_var_model_id=i'=>\$somatic_var_model_id, 'working_dir=s'=>\$working_dir, 'common_name=s'=>\$common_name, 'verbose=i'=>\$verbose);

my $usage=<<INFO;

  Example usage: 
  
  generateClonalityPlot.pl  --somatic_var_model_id=2880746426  --working_dir=/gscmnt/sata132/techd/mgriffit/hgs/hg1/clonality/  --common_name='hg1'
  
  Intro:
  This script attempts to automate the process of creating a 'clonality' plot

  Details:
  --somatic_var_model_id          Model ID for a somatic variation model
  --working_dir                   Directory to place temp files and results
  --common_name                   Human readable name for the patient / sample comparison 
  --verbose                       To display more output, set to 1

INFO

unless ($somatic_var_model_id && $working_dir && $common_name){
  print GREEN, "$usage", RESET;
  exit();
}

if ($verbose){print BLUE, "\n\nCreating clonality plot for $common_name", RESET;}

#Get somatic variation effects dir, tumor bam and normal bam from a somatic variation model ID
my %data_paths;
if ($somatic_var_model_id){
  my $somatic_var_model = Genome::Model->get($somatic_var_model_id);
  if ($somatic_var_model){
    my $somatic_var_build = $somatic_var_model->last_succeeded_build;
    if ($somatic_var_build){
      #... /genome/lib/perl/Genome/Model/Build/SomaticVariation.pm
      $data_paths{root_dir} = $somatic_var_build->data_directory ."/";
      $data_paths{effects_dir} = "$data_paths{root_dir}"."effects/";
      $data_paths{cnvs_hq} = "$data_paths{root_dir}"."variants/cnvs.hq";
      $data_paths{normal_bam} = $somatic_var_build->normal_bam;
      $data_paths{tumor_bam} = $somatic_var_build->tumor_bam;
      my $reference_build = $somatic_var_build->reference_sequence_build;
      $data_paths{reference_fasta} = $reference_build->full_consensus_path('fa');
      $data_paths{display_name} = $reference_build->__display_name__;
    }else{
      print RED, "\n\nA model ID was specified, but a successful build could not be found!\n\n", RESET;
      exit();
    }
  }else{
    print RED, "\n\nA model ID was specified, but it could not be found!\n\n", RESET;
    exit();
  }
}

my $somatic_effects_dir = $data_paths{effects_dir};

#Make sure the specified parameters are correct
$somatic_effects_dir = &checkDir('-dir'=>$somatic_effects_dir, '-clear'=>"no");
$working_dir = &checkDir('-dir'=>$working_dir, '-clear'=>"no");


#Step 1 - gather the tier 1-3 snv files from the build:
my $tier1_snv_file = $somatic_effects_dir . "snvs.hq.novel.tier1.v2.bed";
my $tier2_snv_file = $somatic_effects_dir . "snvs.hq.novel.tier2.v2.bed";
my $tier3_snv_file = $somatic_effects_dir . "snvs.hq.novel.tier3.v2.bed";
my $cp_cmd = "cp $tier1_snv_file $tier2_snv_file $tier3_snv_file $working_dir";
if ($verbose){print YELLOW, "\n\n$cp_cmd", RESET;}
system($cp_cmd);


#Step 2 - put them together in one file:
my $cat_cmd = "cat $working_dir"."snvs* > $working_dir"."allsnvs.hq.novel.tier123.v2.bed";
if ($verbose){print YELLOW, "\n\n$cat_cmd", RESET;}
system($cat_cmd);

#Step 3 - take it out of bed format to be fed into bam-readcounts:
my $adapted_file ="$working_dir"."allsnvs.hq.novel.tier123.v2.bed.adapted";
my $awk_cmd = "awk \'{OFS=\"\\t\";FS=\"\\t\";}{print \$1,\$3,\$3,\$4}\' $working_dir"."allsnvs.hq.novel.tier123.v2.bed | sed \'s/\\//\\t/g\' > $adapted_file";
if ($verbose){print YELLOW, "\n\n$awk_cmd", RESET;}
system($awk_cmd);


#Step 4 - run bam readcounts and assess the particular reads for the reference and variant and print out details about the numbers of reads and the percentages for multiple bam files:
my $tumor_bam = $data_paths{tumor_bam};
my $normal_bam = $data_paths{normal_bam};
my $readcounts_outfile = "$adapted_file".".readcounts";
my $read_counts_cmd = "$script_dir"."borrowed/ndees/give_me_readcounts.pl  --sites_file=$adapted_file --bam_list=\"Tumor:$tumor_bam,Normal:$normal_bam\" --reference_fasta=$data_paths{reference_fasta} --output_file=$readcounts_outfile";
if ($verbose){print YELLOW, "\n\n$read_counts_cmd", RESET;}
system($read_counts_cmd);


#Step 5 - create a varscan-format file from these outputs:
#perl ~kkanchi/bin/create_pseudo_varscan.pl     allsnvs.hq.novel.tier123.v2.bed.adapted     allsnvs.hq.novel.tier123.v2.bed.adapted.readcounts     >     allsnvs.hq.novel.tier123.v2.bed.adapted.readcounts.varscan
my $readcounts_varscan_file = "$readcounts_outfile".".varscan";
my $varscan_format_cmd = "$script_dir"."borrowed/kkanchi/create_pseudo_varscan.pl $adapted_file $readcounts_outfile > $readcounts_varscan_file";
if ($verbose){print YELLOW, "\n\n$varscan_format_cmd", RESET;}
system($varscan_format_cmd);


#TODO: Replace steps 3-5 above by using the following script:
#gmt validation prepare-wgs-for-clonality-plot --help
#USAGE
# gmt validation prepare-wgs-for-clonality-plot --output-file=? --snv-file=? [--bam-file=?]
#    [--genome-build=?] [--min-mapping-quality=?] [--output-readcounts-file=?] [--readcounts-file=?]
#Use the optional --bam-file input so that readcounts are generated for you.



#Step 6 - Take the cnvs.hq file from the somatic-variation build, and run the cna-seg tool to create known regions of copy-number
#Specify config file paths for hg19/build37
#gmt copy-number cna-seg --copy-number-file=/gscmnt/ams1184/info/model_data/2875816457/build111674790/variants/cnvs.hq  --min-markers=4  --detect-somatic  --centromere-file=/gscmnt/sata186/info/medseq/kchen/work/SolexaCNV/scripts/centromere.hg19.csv  --gap-file=/gscmnt/sata186/info/medseq/kchen/work/SolexaCNV/scripts/hg19gaps.csv  --output-file=hg1.cnvhmm

#Make a copy of the cnvs.hq file
$cp_cmd = "cp $data_paths{cnvs_hq} $working_dir";
if ($verbose){print YELLOW, "\n\n$cp_cmd", RESET;}
system($cp_cmd);
my $chmod_cmd = "chmod 664 $working_dir"."cnvs.hq";
system ($chmod_cmd);

my $centromere_file;
my $gap_file;
if ($data_paths{display_name} =~ /NCBI\-human\-build36/){
  $centromere_file = "/gscmnt/sata132/techd/mgriffit/reference_annotations/hg18/ideogram/centromere.hg18.csv";
  $gap_file = "/gscmnt/sata132/techd/mgriffit/reference_annotations/hg18/ideogram/hg18gaps.csv";
}elsif($data_paths{display_name} =~ /GRCh37\-lite\-build37/){
  $centromere_file = "/gscmnt/sata132/techd/mgriffit/reference_annotations/hg19/ideogram/centromere.hg19.csv";
  $gap_file = "/gscmnt/sata132/techd/mgriffit/reference_annotations/hg19/ideogram/hg19gaps.csv";
}else{
  print RED, "\n\nUnrecognized build - unable to identify centromere and gapfiles, you will need to generate these and place in the appropriate location\n\n", RESET;
  exit();
}
my $cnvhmm_file = "$working_dir"."cnaseq.cnvhmm";
my $cnaseg_cmd = "gmt copy-number cna-seg --copy-number-file=$data_paths{cnvs_hq}  --min-markers=4  --detect-somatic  --centromere-file=$centromere_file  --gap-file=$gap_file  --output-file=$cnvhmm_file";
if ($verbose){print YELLOW, "\n\n$cnaseg_cmd", RESET;}
system($cnaseg_cmd);


#Step 7 - then, put the cna-seg and varscan-format snv file together in this clonality tool:
#gmt validation clonality-plot     --cnvhmm-file     /gscuser/ndees/103/wgs/SV_somatic/CNV/aml103.cnvhmm     --output-image     aml103.clonality.pdf     --r-script-output-file     clonality.R     --varscan-file     allsnvs.hq.novel.tier123.v2.bed.adapted.readcounts.varscan     --analysis-type     wgs     --sample-id     'AML103'     --positions-highlight     IL2RA_NF1_positions

#gmt validation clonality-plot  --cnvhmm-file='/gscmnt/sata132/techd/mgriffit/hg1/clonality/hg1.cnvhmm'  --output-image hg1.clonality.pdf  --r-script-output-file clonality.R  --varscan-file allsnvs.hq.novel.tier123.v2.bed.adapted.readcounts.varscan  --analysis-type wgs  --sample-id 'HG1'
my $output_image_file = "$working_dir"."$common_name".".clonality.pdf";
my $r_script_file = "$working_dir"."clonality.R";
my $uc_common_name = uc($common_name);
my $clonality_cmd = "gmt validation clonality-plot  --cnvhmm-file=$cnvhmm_file  --output-image=$output_image_file  --r-script-output-file=$r_script_file  --varscan-file=$readcounts_varscan_file  --analysis-type=wgs  --sample-id='$uc_common_name'";
if ($verbose){print YELLOW, "\n\n$clonality_cmd\n", RESET;}
system($clonality_cmd);

#Keep the files that were needed to run the cna-seg and clonality plot steps so that someone can rerun with different parameters 
#Delete intermediate files though?

if ($verbose){print "\n\n";}

exit();



