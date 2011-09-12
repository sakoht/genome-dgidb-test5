package Genome::Model::Tools::Capture::CreateMafFile;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# CreateMafFile - Constructs a MAF format file if you provide variants and annotation
#
#  AUTHOR:   Dan Koboldt (dkoboldt@genome.wustl.edu)
#
#  CREATED:  12/09/2009 by D.K.
#  MODIFIED: 11/30/2010 by ckandoth
#
#  NOTES:
#  11/30/2010, ckandoth: MAF standard variant classifications are now used
#
#####################################################################################################################################

use strict;
use warnings;
use FileHandle;
use Genome; # using the namespace authorizes Class::Autouse to lazy-load modules under it

## Declare global statistics hash ##
my %stats = ();

class Genome::Model::Tools::Capture::CreateMafFile {
  is => 'Command',

  has => [ # specify the command's single-value properties (parameters) <---
    snv_file  => { is => 'Text', doc => "File of SNVs to include", is_optional => 1 },
    snv_annotation_file => { is => 'Text', doc => "SNVs with WU annotations", is_optional => 1 },
    indel_file  => { is => 'Text', doc => "File of Indels to include", is_optional => 1 },
    indel_annotation_file => { is => 'Text', doc => "Indels with WU annotations", is_optional => 1 },
    somatic_status => { is => 'Text', doc => "Predicted somatic status of variant (Germline/Somatic/LOH) [Somatic]", is_optional => 1 },
    genome_build  => { is => 'Text', doc => "Reference genome build used for coordinates [36]", is_optional => 1 },
    phase  => { is => 'Text', doc => "Project Phase [Phase_IV]", is_optional => 1 },
    tumor_sample  => { is => 'Text', doc => "Tumor sample name [Tumor]", is_optional => 1 },
    normal_sample  => { is => 'Text', doc => "Normal sample name [Normal]", is_optional => 1 },
    source  => { is => 'Text', doc => "Library source (PCR/Capture) [Capture]", is_optional => 1 },
    platform  => { is => 'Text', doc => "Sequencing platform [Illumina GAIIx]", is_optional => 1 },
    center  => { is => 'Text', doc => "Sequencing center [genome.wustl.edu]", is_optional => 1 },
    normal_gt_field  => { is => 'Text', doc => "1-based column number of field containing the normal genotype", is_optional => 1 },
    tumor_gt_field  => { is => 'Text', doc => "1-based column number of field containing the tumor genotype", is_optional => 1 },
    output_file  => { is => 'Text', doc => "Output file for MAF format", is_optional => 0 },
  ],
};

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
  "Build MAF files for predicted variants from capture projects"
}

sub help_synopsis {
  return <<EOS
Build MAF files for predicted variants from capture projects
EXAMPLE:   gmt capture create-maf-file ...
EOS
}

sub help_detail { # this is what the user will see with the longer version of help. <---
  return <<EOS
EOS
}

################################################################################################
# Execute - the main program logic
#
################################################################################################

sub execute {                               # replace with real execution logic.
  my $self = shift;
$DB::single = 1;
  ## Get required parameters ##
  my $snv_file = $self->snv_file;
  my $snv_annotation_file = $self->snv_annotation_file;
  my $output_file = $self->output_file;
  my $indel_file = $self->indel_file;
  my $indel_annotation_file = $self->indel_annotation_file;

  ## Declare parameter defaults ##
  my $genome_build = "36";
  my $phase = "Phase_IV";
  my $source = "Capture";
  my $platform = "Illumina GAIIx";
  my $center = "genome.wustl.edu";
  my $somatic_status = "Somatic";
  my $tumor_sample = "Tumor";
  my $normal_sample = "Normal";

  ## Use user-provided parameters if defined ##
  $genome_build = $self->genome_build if($self->genome_build);
  $phase = $self->phase if($self->phase);
  $source = $self->source if($self->source);
  $platform = $self->platform if($self->platform);
  $somatic_status = $self->somatic_status if($self->somatic_status);
  $center = $self->center if($self->center);
  $tumor_sample = $self->tumor_sample if($self->tumor_sample);
  $normal_sample = $self->normal_sample if($self->normal_sample);

  ## Verify existence of files ##
  if(!(-e $snv_file || -e $indel_file))
  {
    warn "Error: SNV file or indel file does not exist!\n";
    return 0;
  }

  ## Open the outfile ##
  open(OUTFILE, ">$output_file") or die "Can't open output file: $!\n";
  print OUTFILE "Hugo_Symbol\tEntrez_Gene_Id\tCenter\tNCBI_Build\tChromosome\tStart_position\t",
                "End_position\tStrand\tVariant_Classification\tVariant_Type\tReference_Allele\t",
                "Tumor_Seq_Allele1\tTumor_Seq_Allele2\tdbSNP_RS\tdbSNP_Val_Status\t",
                "Tumor_Sample_Barcode\tMatched_Norm_Sample_Barcode\tMatch_Norm_Seq_Allele1\t",
                "Match_Norm_Seq_Allele2\tTumor_Validation_Allele1\tTumor_Validation_Allele2\t",
                "Match_Norm_Validation_Allele1\tMatch_Norm_Validation_Allele2\t",
                "Verification_Status\tValidation_Status\tMutation_Status\tSequencing_Phase\t",
                "Sequence_Source\tValidation_Method\tScore\tBAM_file\tSequencer\n";

  ## Load the annotations ##
  if( $snv_annotation_file ) {
    my %annotations = load_annotations( $snv_annotation_file );
    my $input = new FileHandle ($snv_file);
    my $lineCounter = 0;

    while (<$input>)
    {
      chomp;
      my $line = $_;
      $lineCounter++;

      my @lineContents = split(/\t/, $line);

      next if $line =~ /gene_name/;
      my $chrom = $lineContents[0];
      my $chr_start = $lineContents[1];
      my $chr_stop = $lineContents[2];
      my $ref = $lineContents[3];
      my $var = $lineContents[4];
      my $key = "$chrom\t$chr_start\t$chr_stop\t$ref\t$var";

      if($annotations{$key})
      {
        my $tumor_allele1 = $ref;
        my $tumor_allele2 = $var;
        my $normal_allele1 = $ref;
        my $normal_allele2 = $ref;
        
        ## Parse the normal genotype ##
        if($self->normal_gt_field && $lineContents[$self->normal_gt_field - 1])
        {
          my $normal_call= $lineContents[$self->normal_gt_field - 1];
          if($normal_call eq "A" || $normal_call eq "C" || $normal_call eq "G" || $normal_call eq "T")
          {
            $normal_allele1 = $normal_allele2 = $normal_call;
          }
          else
          {
            $normal_allele1 = $ref;
            $normal_allele2 = code_to_var_allele($ref, $normal_call);
          }
        }

        ## Parse the tumor genotype ##
        if($self->tumor_gt_field && $lineContents[$self->tumor_gt_field - 1])
        {
          my $tumor_call= $lineContents[$self->tumor_gt_field - 1];
          if($tumor_call eq "A" || $tumor_call eq "C" || $tumor_call eq "G" || $tumor_call eq "T")
          {
            $tumor_allele1 = $tumor_allele2 = $tumor_call;
          }
          else
          {
            $tumor_allele1 = $ref;
            $tumor_allele2 = code_to_var_allele($ref, $tumor_call);
          }
        }
        
        my ( $var_type, $gene, $trv_type ) = split( /\t/, $annotations{$key} );
        my $var_class = trv_to_mutation_type( $trv_type );
        my $maf_line = "$gene\t0\t$center\t$genome_build\t$chrom\t$chr_start\t$chr_stop\t+\t";
        $maf_line .=  "$var_class\t$var_type\t$ref\t";
        $maf_line .=  "$tumor_allele1\t$tumor_allele2\t";
        $maf_line .=  "\t\t"; #dbSNP
        $maf_line .=  "$tumor_sample\t$normal_sample\t$normal_allele1\t$normal_allele2\t";
        $maf_line .=  "\t\t\t\t"; # Validation alleles
        $maf_line .=  "Unknown\tUnknown\t$somatic_status\t";
        $maf_line .=  "$phase\tCapture\t";
        $maf_line .=  "\t"; # Val method
        $maf_line .=  "1\t"; # Score
        $maf_line .=  "dbGAP\t";
        $maf_line .=  "$platform\n";

        print OUTFILE "$maf_line";
      }
    }

    close($input);
  }

  ## Load the annotations ##
  if( $indel_annotation_file ) {
    my %annotations = load_annotations( $indel_annotation_file );
    my $input = new FileHandle ($indel_file);
    my $lineCounter = 0;

    while (<$input>)
    {
      chomp;
      my $line = $_;
      $lineCounter++;

      my @lineContents = split(/\t/, $line);
      next if $line =~ /gene_name/;
      my $chrom = $lineContents[0];
      my $chr_start = $lineContents[1];
      my $chr_stop = $lineContents[2];
      my $ref = $lineContents[3];
      my $var = $lineContents[4];
      $ref = "-" if($ref eq "0");
      $var = "-" if($var eq "0");

      my $key = "$chrom\t$chr_start\t$chr_stop\t$ref\t$var";

      if($annotations{$key})
      {
          my ( $var_type, $gene, $trv_type ) = split( /\t/, $annotations{$key} );
          my $var_class = trv_to_mutation_type( $trv_type );

          my $tumor_allele1 = $ref;
          my $tumor_allele2 = $var;
          my $normal_allele1 = $ref;
          my $normal_allele2 = $ref;

          ## Parse the normal genotype ##
          if($self->normal_gt_field && $lineContents[$self->normal_gt_field - 1])
          {
              my $normal_call= $lineContents[$self->normal_gt_field - 1];
              if($normal_call =~ '\*')
              {
                  $normal_allele1 = $ref;
                  $normal_allele2 = $var;
              }
              else
              {
                  $normal_allele1 = $normal_allele2 = $var;
              }
          }

          ## Parse the tumor genotype ##
          if($self->tumor_gt_field && $lineContents[$self->tumor_gt_field - 1])
          {
              my $tumor_call= $lineContents[$self->tumor_gt_field - 1];
              if($tumor_call =~ '\*')
              {
                  $tumor_allele1 = $ref;
                  $tumor_allele2 = $var;
              }
              else
              {
                  $tumor_allele1 = $tumor_allele2 = $var;
              }
          }


          my $maf_line =  "$gene\t0\t$center\t$genome_build\t$chrom\t$chr_start\t$chr_stop\t+\t";
          $maf_line .=  "$var_class\t$var_type\t$ref\t";
          $maf_line .=  "$tumor_allele1\t$tumor_allele2\t";
          $maf_line .=  "\t\t"; #dbSNP
          $maf_line .=  "$tumor_sample\t$normal_sample\t$normal_allele1\t$normal_allele2\t";
          $maf_line .=  "\t\t\t\t"; # Validation alleles
          $maf_line .=  "Unknown\tUnknown\t$somatic_status\t";
          $maf_line .=  "$phase\tCapture\t";
          $maf_line .=  "\t"; # Val method
          $maf_line .=  "1\t"; # Score
          $maf_line .=  "dbGAP\t";
          $maf_line .=  "$platform\n";
          print OUTFILE "$maf_line";
      }
  }

  close($input);
  }
  close(OUTFILE);
  return 1;                               # exits 0 for true, exits 1 for false (retval/exit code mapping is overridable)
}

#############################################################
# load_annotations - Parses annotation files and construct a hash
#
#############################################################

sub load_annotations
{
    my $annotation_file = shift(@_);

    ## Parse the annotation file ##
    my %annotations = ();
    my $input = new FileHandle ($annotation_file);
    my $lineCounter = 0;

    while (<$input>)
    {
        chomp;
        my $line = $_;
        next if( $line =~ m/chromosome_name/ );
        $lineCounter++;

        my @lineContents = split( /\t/, $line );
        my $chrom = $lineContents[0];
        my $chr_start = $lineContents[1];
        my $chr_stop = $lineContents[2];
        my $ref = $lineContents[3];
        my $var = $lineContents[4];

        $ref = "-" if($ref eq "0");
        $var = "-" if($var eq "0");

        my $var_type = $lineContents[5];
        my $gene_name = $lineContents[6];
        my $trv_type = $lineContents[13];
        my $key = "$chrom\t$chr_start\t$chr_stop\t$ref\t$var";
        $annotations{$key} = "$var_type\t$gene_name\t$trv_type";
    }

    close( $input );
    return( %annotations );
}

#############################################################
# trv_to_mutation_type - Converts WU var types to MAF variant classifications
#
#############################################################
sub trv_to_mutation_type
{
    my $trv_type = shift;

    return( "Missense_Mutation" ) if( $trv_type eq "missense" );
    return( "Nonsense_Mutation" ) if( $trv_type eq "nonsense" || $trv_type eq "nonstop" );
    return( "Silent" ) if( $trv_type eq "silent" );
    return( "Splice_Site" ) if( $trv_type eq "splice_site" || $trv_type eq "splice_site_del" || $trv_type eq "splice_site_ins" );
    return( "Frame_Shift_Del" ) if( $trv_type eq "frame_shift_del" );
    return( "Frame_Shift_Ins" ) if( $trv_type eq "frame_shift_ins" );
    return( "In_Frame_Del" ) if( $trv_type eq "in_frame_del" );
    return( "In_Frame_Ins" ) if( $trv_type eq "in_frame_ins" );
    return( "RNA" ) if( $trv_type eq "rna" );
    return( "3'UTR" ) if( $trv_type eq "3_prime_untranslated_region" );
    return( "5'UTR" ) if( $trv_type eq "5_prime_untranslated_region" );
    return( "3'Flank" ) if( $trv_type eq "3_prime_flanking_region" );
    return( "5'Flank" ) if( $trv_type eq "5_prime_flanking_region" );

    return( "Intron" ) if( $trv_type eq "intronic" || $trv_type =~ /^splice_region/ );
    return( "Targeted_Region" ) if( $trv_type eq "-" );

    warn( "Unknown mutation type $trv_type\n" );
    return( "Unknown" );
}


## Convert an IUPAC code to 

sub code_to_var_allele
{
    my $ref = shift(@_);
    my $code = shift(@_);        

    return("A") if($code eq "A");
    return("C") if($code eq "C");
    return("G") if($code eq "G");
    return("T") if($code eq "T");

    if($code eq "M")
    {
        if($ref eq "A")
        {
            return("C");
        }
        else
        {
            return("A");
        }
    }

    if($code eq "R")
    {
        if($ref eq "A")
        {
            return("G");
        }
        else
        {
            return("A");
        }
    }
    if($code eq "W")
    {
        if($ref eq "A")
        {
            return("T");
        }
        else
        {
            return("A");
        }          
    }

    if($code eq "S")
    {
        if($ref eq "C")
        {
            return("G");
        }
        else
        {
            return("C");
        }          
    }

    if($code eq "Y")
    {
        if($ref eq "C")
        {
            return("T");
        }
        else
        {
            return("C");
        }          
    }
    if($code eq "K")
    {
        if($ref eq "G")
        {
            return("T");
        }
        else
        {
            return("G");
        }          
    }


    warn "Unrecognized ambiguity code $code!\n";

    return("N");	
}


1;
