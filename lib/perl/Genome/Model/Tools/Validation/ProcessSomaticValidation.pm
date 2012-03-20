package Genome::Model::Tools::Validation::ProcessSomaticValidation;

use warnings;
use strict;
use IO::File;
use Genome;
use Sort::Naturally qw(nsort);
use Genome::Info::IUB;

class Genome::Model::Tools::Validation::ProcessSomaticValidation {
  is => 'Command',
  has_input => [
      somatic_validation_model_id => {
          is => 'Text',
          doc => "ID of SomaticValidation model",
      },

      output_dir => {
          is => 'Text',
          doc => "Directory where output will be stored (under a subdirectory with the sample name)",
      },

      ],

  has_optional_input => [

      variant_list =>{
          is => 'Text',
          is_optional => 1,
          doc => "list of variants that we're trying to validate, in bed format",
      },

      somatic_variation_model_id =>{
          is => 'Text',
          is_optional => 1,
          doc => "somatic variation model that was used to call the variants in the first place. These bams will be used to id variants with good coverage here, but poor coverage in validation that might be real",
      },

      igv_reference_name =>{
          is => 'Text',
          is_optional => 1,
          doc => "name of the igv reference to use",
          default => "reference_build36",
      },

      tumor_only =>{
          is => 'Boolean',
          is_optional => 1,
          default => 0,
          doc => "model is an extension with only tumor data",
      },

      filter_sites =>{
          is => 'Text',
          is_optional => 1,
          doc => "list of sites to be removed in bed format. (example - removing cell-line sites from tumors grown on them)",
      },

      restrict_to_target_regions =>{
          is => 'Boolean',
          is_optional => 1,
          default => 1,
          doc => "only keep snv calls within the target regions. These are pulled from the build",
      },

      tier1_only =>{
          is => 'Boolean',
          is_optional => 1,
          default => 0,
          doc => "only keep and review calls that are tier 1",
      },

      tier_file_location =>{
          is => 'String',
          is_optional => 1,
          doc => "if tier1-only is specified, this needs to be a path to the appropriate tiering files",
      },

      ##restrict to targeted region - grab from build

      # read_review => {
      #     is => 'Boolean',
      #     doc => "Read existing manual review files and create WU annotation files per case",
      #     is_optional => 1,
      #     default => 0
      #   },

      ],
};


sub help_detail {
  return <<HELP;
Given a SomaticValidation model, this tool will gather the resulting variants, remove
off-target sites, tier the variants, optionally filter them, and match them up with the
initial predictions sent for validation.  It will then divide them into categories (validated,
non-validated, and new calls). New calls are prepped for manual review in the review/ directory.
HELP
}

sub _doc_authors {
  return <<AUTHS;
 Chris Miller
AUTHS
}

sub bedToAnno{
    my ($chr,$start,$stop,$ref,$var) = split("\t",$_[0]);
    #print STDERR join("|",($chr,$start,$stop,$ref,$var)) . "\n";
    if ($ref =~ /^\-/){ #indel INS
        $stop = $stop+1;
    } else { #indel DEL or SNV
        $start = $start+1;
    }
    return(join("\t",($chr,$start,$stop,$ref,$var)));
}

sub annoToBed{
    my ($chr,$start,$stop,$ref,$var) = split("\t",$_[0]);
    if ($ref =~ /^\-/){ #indel INS
        $stop = $stop-1;
    } else { #indel DEL or SNV
        $start = $start-1;
    }
    return(join("\t",($chr,$start,$stop,$ref,$var)));
}

sub intersects{
    my ($st,$sp,$st2,$sp2) = @_;
    if((($sp2 >= $st) && ($sp2 <= $sp)) ||
       (($sp >= $st2) && ($sp <= $sp2))){
        return 1;
    }
    return 0;
}

sub fixIUB{
    my ($ref,$var) = @_;
    my @vars = Genome::Info::IUB->variant_alleles_for_iub($ref,$var);
    return @vars;
}


sub execute {
  my $self = shift;
  my $tumor_only = $self->tumor_only;
  my $somatic_validation_model_id = $self->somatic_validation_model_id;
  my $output_dir = $self->output_dir;
  $output_dir =~ s/(\/)+$//; # Remove trailing forward-slashes if any

  # Check on the input data before starting work
  my $model = Genome::Model->get( $somatic_validation_model_id );
  print STDERR "ERROR: Could not find a model with ID: $somatic_validation_model_id\n" unless( defined $model );
  print STDERR "ERROR: Output directory not found: $output_dir\n" unless( -e $output_dir );
  return undef unless( defined $model && -e $output_dir );


  #grab the info from all of the models
  my %bams; # Hash to store the model info
  my $build = $model->last_succeeded_build;
  unless( defined($build) ){
      print STDERR "WARNING: Model ", $model->id, "has no succeeded builds\n";
      return undef;
  }

  my $ref_seq_build_id = $model->reference_sequence_build->build_id;
  my $ref_seq_build = Genome::Model::Build->get($ref_seq_build_id);
  my $ref_seq_fasta = $ref_seq_build->full_consensus_path('fa');
  my $sample_name = $model->tumor_sample->name;
  print STDERR "processing model with sample_name: " . $sample_name . "\n";
  my $tumor_bam = $build->tumor_bam;
  my $build_dir = $build->data_directory;


  my $normal_bam;
  unless($tumor_only){
      my $normal_bam = $build->normal_bam;
  }


  # Check if the necessary files exist in this build
  my $snv_file = "$build_dir/variants/snvs.hq.bed";
  unless( -e $snv_file ){
      die "ERROR: SNV results annotations for $sample_name not found at $snv_file\n";
  }
  my $indel_file = "$build_dir/variants/indels.hq.bed";
  unless( -e $indel_file ){
      die "ERROR: INDEL results annotations for $sample_name not found at $indel_file\n";
  }


  # create subdirectories, get files in place
  mkdir "$output_dir/$sample_name" unless( -e "$output_dir/$sample_name" );
  mkdir "$output_dir/$sample_name/snvs" unless( -e "$output_dir/$sample_name/snvs" );
  mkdir "$output_dir/$sample_name/indels" unless( -e "$output_dir/$sample_name/indels" );
  mkdir "$output_dir/review" unless( -e "$output_dir/review" );
  `ln -s $build_dir $output_dir/$sample_name/build_directory`;
  `ln -s $snv_file $output_dir/$sample_name/snvs/` unless( -e "$output_dir/$sample_name/snvs/$snv_file");
  `ln -s $indel_file $output_dir/$sample_name/indels/` unless( -e "$output_dir/$sample_name/indels/$indel_file");
  $snv_file = "$output_dir/$sample_name/snvs/snvs.hq.bed";
  $indel_file = "$output_dir/$sample_name/indels/indels.hq.bed";
  

  #-------------------------------------------------
  #store the previously called variants into a hash
  my %prevCalls;
  if( -e $self->variant_list){
      my $inFh = IO::File->new( $self->variant_list ) || die "can't open file\n";
      while( my $line = $inFh->getline )
      {
          chomp($line);
          #handle either 5 col (Ref\tVar) or 4 col (Ref/Var) bed
          my ( $chr, $start, $stop, $ref, $var ) = split( /\t/, $line );
          if($ref =~ /\//){
              ( $ref, $var ) = split(/\//, $ref);
          }
          $ref =~ s/0/-/g;
          $var =~ s/0/-/g;
          
          my @vars = fixIUB($ref, $var);
          foreach my $v (@vars){
              $prevCalls{join("\t",($chr, $start, $stop, $ref, $v ))} = 0;
          }
      }
      close($inFh);

  } else {
      print STDERR "WARNING: bed file of targeted variants not found for $sample_name.\nAssuming that there were no calls for this model (and it was an extension experiment)\n";
  }

  #-------------------------------------------------
  #filter out the off-target regions, if target regions are available
  if($self->restrict_to_target_regions){
      print STDERR "Filtering out off-target regions...\n";
      my %targetRegions;
      my $featurelist_id = $model->target_region_set->id;
      my $featurelist = Genome::FeatureList->get($featurelist_id)->file_path;
      if ( -e $featurelist ){
          my $inFh = IO::File->new( $featurelist ) || die "can't open file\n";
          while( my $line = $inFh->getline )
          {
              chomp($line);
              my ( $chr, $start, $stop, @rest) = split( /\t/, $line );
              #remove chr if present
              $chr =~ s/^chr//g;
              $targetRegions{$chr}{join("\t",($start, $stop))} = 0;
          }
          close($inFh);


          #compare the snvs to the targets
          open(TARFILE,">$snv_file.ontarget") || die ("couldn't open target file");
          $inFh = IO::File->new( $snv_file ) || die "can't open file\n";
          while( my $line = $inFh->getline )
          {
              chomp($line);
              my ( $chr, $start, $stop, @rest ) = split( /\t/, $line );

              #if we run into huge lists, this will be slow - refactor to use joinx - TODO
              my $found = 0;
              foreach my $pos (keys(%{$targetRegions{$chr}})){
                  my ($tst, $tsp) = split("\t",$pos);
                  if(intersects($start,$stop,$tst,$tsp)){
                      $found = 1;
                  }
              }
              if($found){
                  print TARFILE $line . "\n"; 
              }
          }
          close($inFh);
          close(TARFILE);
          $snv_file = "$snv_file.ontarget";


          #compare the indels to the targets
          open(TARFILE,">$indel_file.ontarget") || die ("couldn't open target file");
          $inFh = IO::File->new( $indel_file ) || die "can't open file\n";
          while( my $line = $inFh->getline )
          {
              chomp($line);
              my ( $chr, $start, $stop, @rest ) = split( /\t/, $line );
              foreach my $pos (keys(%{$targetRegions{$chr}})){
                  my ($tst, $tsp) = split("\t",$pos);
                  if(intersects($start,$stop,$tst,$tsp)){
                      print TARFILE $line . "\n";
                  }
              }
          }
          close($inFh);
          close(TARFILE);
          $indel_file = "$indel_file.ontarget";

      } else {
          print STDERR "WARNING: feature list not found at location $featurelist\nNo target region filtering being done\n";
      }
  }

  ##------------------------------------------------------
  #remove all but tier 1 sites, if that option is specified
  if($self->tier1_only){
  print STDERR "Doing Tiering...\n";
      my $tier_cmd = Genome::Model::Tools::FastTier::FastTier->create(
          tier_file_location => $self->tier_file_location,
          variant_bed_file => $snv_file,
      );
      unless ($tier_cmd->execute) {
          die "Failed to tier variants successfully.\n";
      }
      $snv_file = "$snv_file.tier1";

      $tier_cmd = Genome::Model::Tools::FastTier::FastTier->create(
          tier_file_location => $self->tier_file_location,
          variant_bed_file => $indel_file,
      );
      unless ($tier_cmd->execute) {
          die "Failed to tier variants successfully.\n";
      }
      $indel_file = "$indel_file.tier1";
  }


  #-------------------------------------------------
  #remove filter sites specified by the user
  if(defined($self->filter_sites)){
      print STDERR "Applying user-supplied filter...\n";
      if( -e $self->filter_sites){
          my %filterSites;
          #store sites to filter out in a hash
          my $inFh = IO::File->new( $self->filter_sites ) || die "can't open file\n";
          while( my $line = $inFh->getline )
          {
              chomp($line);
              #handle either 5 col (Ref\tVar) or 4 col (Ref/Var) bed
              my ( $chr, $start, $stop, $ref, $var ) = split( /\t/, $line );
              if($ref =~ /\//){
                  ( $ref, $var ) = split(/\//, $ref);
              }
              $ref =~ s/0/-/g;
              $var =~ s/0/-/g;

              my @vars = fixIUB($ref, $var);
              foreach my $v (@vars){            
                  $filterSites{join("\t",($chr, $start, $stop, $ref, $v ))} = 0;
              }
          }
          close($inFh);

          #remove snvs
          open(FILFILE,">$snv_file.filtered") || die ("couldn't open filter file");
          $inFh = IO::File->new( $snv_file ) || die "can't open file\n";
          while( my $line = $inFh->getline )
          {
              chomp($line);
              my ( $chr, $start, $stop, $ref, $var ) = split( /\t/, $line );
              if($ref =~ /\//){
                  ( $ref, $var ) = split(/\//, $ref);
              }
              my @vars = fixIUB($ref, $var);
              foreach my $v (@vars){
                  unless (exists($filterSites{join("\t",($chr, $start, $stop, $ref, $v ))})){
                      print FILFILE $line . "\n";
                  }
              }
          }
          close(FILFILE);
          $snv_file = "$snv_file.filtered";

          #remove indels
          open(FILFILE,">$indel_file.filtered") || die ("couldn't open filter file");
          $inFh = IO::File->new( $indel_file ) || die "can't open file\n";
          while( my $line = $inFh->getline )
          {
              chomp($line);
              my ( $chr, $start, $stop, $ref, $var ) = split( /\t/, $line );
              if($ref =~ /\//){
                  ( $ref, $var ) = split(/\//, $ref);
              }

              unless (exists($filterSites{join("\t",($chr, $start, $stop, $ref, $var ))})){
                  print FILFILE $line . "\n";
              }
          }
          close(FILFILE);
          $indel_file = "$indel_file.filtered";

      } else {
          die("filter sites file does not exist: " . $self->filter_sites);
      }
  }


  #-------------------------------------------------
  print "Classifying snvs and indels...\n";

  # Grab the high confidence calls from their respective files

  #---first snvs---
  open(VALFILE,">$output_dir/$sample_name/snvs/snvs.validated");
  open(NEWFILE,">$output_dir/$sample_name/snvs/snvs.newcalls");
  open(MISFILE,">$output_dir/$sample_name/snvs/snvs.notvalidated");

  my $inFh = IO::File->new( $snv_file ) || die "can't open file\n";
  while( my $line = $inFh->getline )
  {
      chomp($line);
      my ( $chr, $start, $stop, $ref, $var ) = split( /\t/, $line );
      if($ref =~ /\//){
          ( $ref, $var ) = split(/\//, $ref);
      }

      my $found = 0;
      my @vars = fixIUB($ref, $var);
      foreach my $v (@vars){
      #case 1 - previously found variant, now validated
          if (exists($prevCalls{join("\t",($chr, $start, $stop, $ref, $v ))})){
              $found = 1;
          }
      }
      if($found){
          print VALFILE bedToAnno(join("\t",($chr, $start, $stop, $ref, $var ))) . "\n";
          #mark as found
          $prevCalls{join("\t",($chr, $start, $stop, $ref, $var ))} = 1;
      } else { #case 2: new snv not found in original targets
          print NEWFILE bedToAnno(join("\t",($chr, $start, $stop, $ref, $var ))) . "\n";
      }
  }

  close($inFh);
  #case 3: called in original, not in validation
  foreach my $k (keys(%prevCalls)){
      next if $prevCalls{$k} == 1;
      my ( $chr, $start, $stop, $ref, $var ) = split( /\t/, $k );
      #skip indels
      unless (($ref =~ /-|0/) || ($var =~ /-|0/)){
          print MISFILE bedToAnno(join("\t",($chr, $start, $stop, $ref, $var ))) . "\n";
      }
  }
  
  close(VALFILE);
  close(NEWFILE);
  close(MISFILE);


  #---now indels---
  open(VALFILE,">$output_dir/$sample_name/indels/indels.validated");
  open(NEWFILE,">$output_dir/$sample_name/indels/indels.newcalls");
  open(MISFILE,">$output_dir/$sample_name/indels/indels.notvalidated");
  $inFh = IO::File->new( $indel_file ) || die "can't open file\n";
  while( my $line = $inFh->getline )
  {
      chomp($line);
      my ( $chr, $start, $stop, $ref, $var ) = split( /\t/, $line );
      if($ref =~ /\//){
          ( $ref, $var ) = split(/\//, $ref);
      }
      $ref =~ s/0/-/g;
      $var =~ s/0/-/g;
      #case 1 - previously found variant, now validated
      if (exists($prevCalls{join("\t",($chr, $start, $stop, $ref, $var ))})){
          print VALFILE bedToAnno(join("\t",($chr, $start, $stop, $ref, $var ))) . "\n";
          #mark as found
          $prevCalls{join("\t",($chr, $start, $stop, $ref, $var ))} = 1;
      } else { #case 2: new indel not found in original targets
          print NEWFILE bedToAnno(join("\t",($chr, $start, $stop, $ref, $var ))) . "\n";
      }
  }
  #case 3: called in original, not in validation
  foreach my $k (keys(%prevCalls)){
      next if $prevCalls{$k} == 1;

      my ( $chr, $start, $stop, $ref, $var ) = split( /\t/, $k );
      #only indels
      if (($ref =~ /-/) || ($var =~ /-/)){
          print MISFILE bedToAnno(join("\t",($chr, $start, $stop, $ref, $var ))) . "\n";
      }
  }
  close(VALFILE);
  close(NEWFILE);
  close(MISFILE);


  #add readcounts
  print STDERR "Getting readcounts...\n";
  mkdir "$output_dir/$sample_name/snvs/readcounts";
  foreach my $file ("snvs.validated","snvs.newcalls","snvs.notvalidated"){

      my $dir = "$output_dir/$sample_name/snvs/";
      if( -s "$dir/$file" ){
          unless($tumor_only){
              #get readcounts from the normal bam
              my $normal_rc_cmd = Genome::Model::Tools::Analysis::Coverage::BamReadcount->create(
                  bam_file => $normal_bam,
                  output_file => "$dir/readcounts/$file.nrm.cnt",
                  snv_file => "$dir/$file",
                  genome_build => $ref_seq_fasta,
                  );
              unless ($normal_rc_cmd->execute) {
                  die "Failed to obtain normal readcounts for file $file.\n";
              }
          }

          #get readcounts from the tumor bam
          my $tumor_rc_cmd = Genome::Model::Tools::Analysis::Coverage::BamReadcount->create(
              bam_file => $tumor_bam,
              output_file => "$dir/readcounts/$file.tum.cnt",
              snv_file => "$dir/$file",
              genome_build => $ref_seq_fasta,
              );
          unless ($tumor_rc_cmd->execute) {
              die "Failed to obtain tumor readcounts for file $file.\n";
          }
      }
  }



##we're not going to do this after all - if not called in validation, we just ditch the call

  # #-------------------------------------------------
  # #look at the calls that were missed (case 3 - called in original, failed validation)
  # #to determine whether they were missed due to poor coverage.
  # #if coverage is fine, dump them (most), but if coverage was poor in validation (and good in wgs), send for review
  # #we can only really do this for snvs at the moment, until indel readcounting is tweaked

  # if(defined($self->somatic_variation_model_id)){
  #     print "Getting readcounts...\n";
  #     my $som_var_model = Genome::Model->get( $self->somatic_variation_model_id );

  #     mkdir "$output_dir/$sample_name/snvs/counts";

  #     unless($tumor_only){
  #         print STDERR "nb: " . $normal_bam . "\n";
  #         #get readcounts from the normal sample
  #         my $normal_rc_cmd = Genome::Model::Tools::Analysis::Coverage::BamReadcount->create(
  #             bam_file => $normal_bam,
  #             output_file => "$output_dir/$sample_name/snvs/counts/snvs.notvalidated.nrm.counts",
  #             snv_file => "$output_dir/$sample_name/snvs/snvs.notvalidated.var",
  #             genome_build => $ref_seq_fasta,
  #             );
  #         unless ($normal_rc_cmd->execute) {
  #             die "Failed to obtain normal readcounts.\n";
  #         }
  #     }

  #     #get readcounts from the tumor sample
  #     my $tumor_rc_cmd = Genome::Model::Tools::Analysis::Coverage::BamReadcount->create(
  #         bam_file => $tumor_bam,
  #         output_file => "$output_dir/$sample_name/snvs/counts/snvs.notvalidated.nrm.counts",
  #         snv_file => "$output_dir/$sample_name/snvs/snvs.notvalidated.var",
  #         genome_build => $ref_seq_fasta,
  #         );
  #     unless ($tumor_rc_cmd->execute) {
  #         die "Failed to obtain tumor readcounts.\n";
  #     }


  #     #get original bams
  #     my $tumor_bam_var = $som_var_model->tumor_model->last_succeeded_build->whole_rmdup_bam_file;
  #     print STDERR "ERROR: Somatic Variation tumor bam not found\n" unless( -e $tumor_bam_var );

  #     my $normal_bam_var = $som_var_model->normal_model->last_succeeded_build->whole_rmdup_bam_file;
  #     print STDERR "ERROR: Somatic Variation normal bam not found\n" unless( -e $normal_bam_var );

  #     #get readcounts from the original normal sample
  #     my $normal_rc2_cmd = Genome::Model::Tools::Analysis::Coverage::BamReadcount->create(
  #         bam_file => $normal_bam_var,
  #         output_file => "$output_dir/$sample_name/snvs/counts/snvs.notvalidated.tum.orig.counts.orig",
  #         snv_file => "$output_dir/$sample_name/snvs/snvs.notvalidated.var",
  #         genome_build => $ref_seq_fasta,
  #         );
  #     unless ($normal_rc2_cmd->execute) {
  #         die "Failed to obtain normal readcounts.\n";
  #     }

  #     #get readcounts from the original tumor sample
  #     my $tumor_rc2_cmd = Genome::Model::Tools::Analysis::Coverage::BamReadcount->create(
  #         bam_file => $tumor_bam_var,
  #         output_file => "$output_dir/$sample_name/snvs/counts/snvs.notvalidated.nrm.counts.orig",
  #         snv_file => "$output_dir/$sample_name/snvs/snvs.notvalidated.var",
  #         genome_build => $ref_seq_fasta,
  #         );
  #     unless ($tumor_rc2_cmd->execute) {
  #         die "Failed to obtain tumor readcounts.\n";
  #     }


  #     #read in all the validation readcounts, keep only those with poor coverage
  #     #require 8 reads in tumor, 6 in normal, per varscan cutoffs

  #     my %poorly_covered_snvs;
  #     open(OUTFILE,">$output_dir/review/$sample_name.poorValCoverage.bed");

  #     unless($tumor_only){
  #         my $inFh = IO::File->new( "$output_dir/$sample_name/snvs/counts/snvs.notvalidated.nrm.counts" ) || die "can't open file\n";
  #         while( my $line = $inFh->getline )
  #         {
  #             chomp($line);
  #             my ( $chr, $start, $ref, $var, $refcnt, $varcnt, $vaf) = split("\t",$line);
  #             if(($refcnt+$varcnt) < 6){
  #                 $poorly_covered_snvs{join(":",( $chr, $start, $ref, $var ))} = 0;
  #             }
  #         }
  #         close($inFh);
  #     }

  #     $inFh = IO::File->new( "$output_dir/$sample_name/snvs/counts/snvs.notvalidated.tum.counts" ) || die "can't open file\n";
  #     while( my $line = $inFh->getline )
  #     {
  #         chomp($line);
  #         my ( $chr, $start, $ref, $var, $refcnt, $varcnt, $vaf) = split("\t",$line);
  #         if(($refcnt+$varcnt) < 8){
  #             $poorly_covered_snvs{join(":",( $chr, $start, $ref, $var ))} = 0;
  #         }
  #     }
  #     close($inFh);

  #     #now, go through the original readcounts, and flag any that do have good coverage for manual review
  #     $inFh = IO::File->new( "$output_dir/$sample_name/snvs/counts/snvs.notvalidated.nrm.counts.orig" ) || die "can't open file\n";
  #     while( my $line = $inFh->getline )
  #     {
  #         chomp($line);
  #         my ( $chr, $start, $ref, $var, $refcnt, $varcnt, $vaf) = split("\t",$line);
  #         if(defined($poorly_covered_snvs{join(":",( $chr, $start, $ref, $var ))})){
  #             if(($refcnt+$varcnt) >= 20){
  #                 $poorly_covered_snvs{join(":",( $chr, $start, $ref, $var ))} = 1;
  #             }
  #         }
  #     }
  #     close($inFh);

  #     my $poorCount = 0;
  #     $inFh = IO::File->new( "$output_dir/$sample_name/snvs/counts/snvs.notvalidated.tum.counts.orig" ) || die "can't open file\n";
  #     while( my $line = $inFh->getline )
  #     {
  #         chomp($line);
  #         my ( $chr, $start, $ref, $var, $refcnt, $varcnt, $vaf) = split("\t",$line);
  #         if(($refcnt+$varcnt) >= 20){
  #             if ($poorly_covered_snvs{join(":",( $chr, $start, $ref, $var ))} == 1){
  #                 #convert to bed while we're at it
  #                 print OUTFILE join("\t",( $chr, $start-1, $start, $ref, $var )) . "\n";
  #                 $poorCount++;
  #             }
  #         }
  #     }
  #     close($inFh);


  #     if($poorCount > 0){
  #         #create the xml file for this 4-way review
  #         my $dumpCovXML = Genome::Model::Tools::Analysis::DumpIgvXmlMulti->create(
  #             bams => join(",",($normal_bam,$tumor_bam,$normal_bam_var,$tumor_bam_var)),
  #             labels => join(",",("validation normal $sample_name","validation tumor $sample_name","original normal $sample_name","original tumor $sample_name")),
  #             output_file => "$output_dir/review/$sample_name.poorValCoverage.xml",
  #             genome_name => $sample_name,
  #             review_bed_file => "$output_dir/review/$sample_name.poorValCoverage.bed",
  #             reference_name => $self->igv_reference_name,
  #             );
  #         unless ($dumpCovXML->execute) {
  #             die "Failed to dump IGV xml for poorly covered sites.\n";
  #         }

  #         print STDERR "--------------------------------------------------------------------------------\n";
  #         print STDERR "Sites for review with poor coverage in validation but good coverage in original are here:\n";
  #         print STDERR "$output_dir/review/$sample_name.poorValCoverage.bed\n";
  #         print STDERR "IGV XML file is here:";
  #         print STDERR "$output_dir/$sample_name/review/poorValCoverage.xml\n\n";
  #     }
  # }


  #-------------------------------------------------
  # look at the new calls that were found in validation, but not in the first build (Case 2 above)
  # in the case of extension experiments, with no previous build, this will be all variants
  print "Gathering new sites...\n";

  if ( -s "$output_dir/$sample_name/snvs/snvs.newcalls"){
      #can't run UHC if tumor-only:
      unless($tumor_only){
          print "Running UHC filter...\n";
          #run the uhc filter to remove solid calls
          my $uhc_cmd = Genome::Model::Tools::Analysis::Coverage::BamReadcount->create(
              normal_bam_file => $normal_bam,
              tumor_bam_file => $tumor_bam,
              output_file => "$output_dir/$sample_name/snvs/snvs.newcalls.passuhc",
              variant_file => "$output_dir/$sample_name/snvs/snvs.newcalls",
              genome_build => $ref_seq_fasta,
              filtered_file => "$output_dir/$sample_name/snvs/snvs.newcalls.failuhc",
              );
          unless ($uhc_cmd->execute) {
              die "Failed to run UHC filter.\n";
          }
      }


      #now get the files together for review
      print "Generating Review files...\n";
      my $revfile;
      if ( -s "$output_dir/$sample_name/snvs/snvs.failuhc"){
          $revfile = "$output_dir/$sample_name/snvs/snvs.failuhc";
      } else {
          $revfile = "$output_dir/$sample_name/snvs/snvs.newcalls";
      }

      open(OUTFILE2,">$output_dir/review/$sample_name.newcalls.bed") || die "couldn't open outfile";

      $inFh = IO::File->new( $revfile ) || die "can't open file\n";
      while( my $line = $inFh->getline )
      {
          chomp($line);
          my ( $chr, $start, $stop, $ref, $var ) = split( /\t/, $line );
          print OUTFILE2 annoToBed(join("\t",($chr, $start, $stop, $ref, $var ))) . "\n";
      }
      close(OUTFILE2);

      my $bam_files;
      my $labels;
      if($tumor_only){
          if(defined($self->somatic_variation_model_id)){
              #add tumor and normal from somatic-variation model
              my $som_var_model = Genome::Model->get( $self->somatic_variation_model_id );
              my $tbam = $som_var_model->tumor_model->last_succeeded_build->whole_rmdup_bam_file;
              my $nbam = $som_var_model->normal_model->last_succeeded_build->whole_rmdup_bam_file;
              $bam_files = join(",",($tumor_bam,$tbam,$nbam));
              $labels = join(",",("validation tumor $sample_name","original tumor $sample_name","original normal $sample_name"));
          } else {
              $bam_files = join(",",($tumor_bam));
              $labels = join(",",("validation tumor $sample_name"));
          }
      } else {
          $bam_files = join(",",($normal_bam,$tumor_bam));
          $labels = join(",",("validation normal $sample_name","validation tumor $sample_name"));
      }


      #create the xml file for review
      my $dumpXML = Genome::Model::Tools::Analysis::DumpIgvXmlMulti->create(
          bams => "$bam_files",
          labels => "$labels",
          output_file => "$output_dir/review/$sample_name.newcalls.xml",
          genome_name => $sample_name,
          review_bed_file => "$output_dir/review/$sample_name.newcalls.bed",
          reference_name => $self->igv_reference_name,
          );
      unless ($dumpXML->execute) {
          die "Failed to dump IGV xml for poorly covered sites.\n";
      }

      print STDERR "\n--------------------------------------------------------------------------------\n";
      print STDERR "Sites to review that were not found original genomes, but were found in validation are here:\n";
      print STDERR "$output_dir/review/$sample_name.newcalls.bed\n";
      print STDERR "IGV XML file is here:";
      print STDERR "$output_dir/review/$sample_name.newcalls.xml\n\n";



  } else {
      print STDERR "No variants found that were called in the validation, but not found in original genomes\n";
  }

  return 1;
}

1;
