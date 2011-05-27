package Genome::Model::Tools::Vcf::VcfMakerVarscan;

use strict;
use warnings;
use Genome;
use File::stat;
use IO::File;
use File::Basename;
use Getopt::Long;
use FileHandle;
use POSIX qw(log10);
use POSIX qw(strftime);
use List::MoreUtils qw(firstidx);
use List::MoreUtils qw(uniq);

class Genome::Model::Tools::Vcf::VcfMakerVarscan {
    is => 'Command',
    has => [
        output_file => {
            is => 'Text',
            is_output => 1,
            doc => "List of mutations in Vcf format",
        },

        chrom => {
            is => 'Text',
            doc => "do only this chromosome" ,
            is_optional => 1,
            default => "",
        },

        skip_header => {
            is => 'Boolean',
            is_optional => 1,
            is_input => 1,
            default => 0,
            doc => 'enable this to skip header output - useful for doing individual chromosomes. Note that the output will be appended to the output file if this is enabled.',
        },

        genome_build => {
            is => 'Text',
            doc => "Reference genome build" ,
            is_optional => 1,
            default => "36",
        },
        
        varscan_file => {
            is => 'Text',
            doc => "varscan output file" ,
            is_optional => 0,
            is_input => 1,
        },

        type => {
            is => 'Text',
            doc => "type of variant calls - one of \"snv\" or \"indel\"" ,
            is_optional => 0,
            is_input => 1,
        },

        sample_id => {
            is => 'Text',
            doc => "unique sample id",
            is_optional => 0,
            is_input => 1,
        },

        dbsnp_file => {
            is => 'Text',
            doc => "dbsnp File - if specified, will label dbSNP sites",
            is_optional => 1,
            is_input => 1,
            default => "",
        },

	],
};


sub help_brief {                            # keep this to just a few words <---
    "Generate Vcf File from Varscan (unformatted) output"
}


sub help_synopsis {
<<'HELP';
Generate a VCF File from Varscan (unformatted) output
HELP
}

sub help_detail {                  # this is what the user will see with the longer version of help. <---
<<'HELP';
Given a varscan output file, this parses the relevant files and creates a VCF containing all the SNVs.
HELP
}



################################################################################################
# Execute - the main program logic
# (continued below functions)
################################################################################################

sub execute {                               # replace with real execution logic.
    my $self = shift;

    my $output_file = $self->output_file;
    my $genome_build = $self->genome_build;
    my $chrom = $self->chrom;
    my $skip_header = $self->skip_header;
    my $varscan_file = $self->varscan_file;
    my $sample_id = $self->sample_id;
    my $type = $self->type;
    my $dbsnp_file = $self->dbsnp_file;

    if(($type ne "snv") && ($type ne "indel")){
        die("\"type\" parameter must be one of \"snv\" or \"indel\"");
    }

###########################################################################
# functions

    #------------------------
    #convert IUB bases to std bases (acgt)
    sub convertIub{
	my ($base) = @_;

	#deal with cases like "A/T" or "C/W"
	if ($base =~/\//){
	    my @bases=split(/\//,$base);
	    my %baseHash;
	    foreach my $b (@bases){
		my $res = convertIub($b);
		my @bases2 = split(",",$res);
		foreach my $b2 (@bases2){
		    $baseHash{$b2} = 0;
		}
	    }
	    return join(",",keys(%baseHash));
	}

	# use a lookup table to return the correct base
	# there's a more efficient way than defining this
	# every time, but meh.
	my %iub_codes;
	$iub_codes{"A"}="A";
	$iub_codes{"C"}="C";
	$iub_codes{"G"}="G";
	$iub_codes{"T"}="T";
	$iub_codes{"U"}="T";
	$iub_codes{"M"}="A,C";
	$iub_codes{"R"}="A,G";
	$iub_codes{"W"}="A,T";
	$iub_codes{"S"}="C,G";
	$iub_codes{"Y"}="C,T";
	$iub_codes{"K"}="G,T";
	$iub_codes{"V"}="A,C,G";
	$iub_codes{"H"}="A,C,T";
	$iub_codes{"D"}="A,G,T";
	$iub_codes{"B"}="C,G,T";
	$iub_codes{"N"}="A,C,G,T";

	return $iub_codes{$base}
    }

    #------------------------
    # generate a GT line from a base and a list of all alleles at the position
    sub genGT{
	my ($base, @alleles) = @_;
        #print "$base -- " . join("|",@alleles) . "\n";
	my @bases = split(",",convertIub($base));
	if (@bases > 1){
	    my @pos;
	    push(@pos, (firstidx{ $_ eq $bases[0] } @alleles));
	    push(@pos, (firstidx{ $_ eq $bases[1] } @alleles));
	    return(join("/", sort(@pos)));
	} else { #only one base
	    my @pos;
	    push(@pos, (firstidx{ $_ eq $bases[0] } @alleles));
	    push(@pos, (firstidx{ $_ eq $bases[0] } @alleles));
	    return(join("/", sort(@pos)));
	}
    }


#-------------------------

#get preceding base using samtools faidx
sub getPrecedingBase{
    my ($chr,$pos) = @_;
    my $base = `samtools faidx ~/sata921/NCBI-human-build36/$chr.fa $chr:$pos-$pos | tail -n 1`;
    chomp($base);
    return($base)
}



    #-------------------------
    # print the VCF header

    sub print_header{
        my ($genome_build, $sample_id, $output_file) = @_;

        open(OUTFILE, ">$output_file") or die "Can't open output file: $!\n";
        my $seqCenter;
        my $file_date = localtime();
        my $reference = "ftp://ftp.ncbi.nlm.nih.gov/genomes/H_sapiens/ARCHIVE/BUILD.36.3/special_requests/assembly_variants/NCBI36_BCCAGSC_variant.fa.gz";

        print OUTFILE "##fileformat=VCFv4.0" . "\n";
        print OUTFILE "##fileDate=" . $file_date . "\n";
        print OUTFILE "##reference=$reference" . "\n";
        print OUTFILE "##phasing=none" . "\n";
        print OUTFILE "##SAMPLE=$sample_id" . "\n";

        #format info
        print OUTFILE "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">" . "\n";
        print OUTFILE "##FORMAT=<ID=GQ,Number=1,Type=Integer,Description=\"Genotype Quality\">" . "\n";
        print OUTFILE "##FORMAT=<ID=DP,Number=1,Type=Integer,Description=\"Total Read Depth\">" . "\n";
        print OUTFILE "##FORMAT=<ID=BQ,Number=1,Type=Integer,Description=\"Average Base Quality corresponding to alleles 0/1/2/3... after software and quality filtering\">" . "\n";
        print OUTFILE "##FORMAT=<ID=MQ,Number=1,Type=Integer,Description=\"Average Mapping Quality corresponding to alleles 0/1/2/3... after software and quality filtering\">" . "\n";
        print OUTFILE "##FORMAT=<ID=AD,Number=1,Type=Integer,Description=\"Allele Depth corresponding to alleles 0/1/2/3... after software and quality filtering\">" . "\n";
        print OUTFILE "##FORMAT=<ID=FA,Number=1,Type=Float,Description=\"Fraction of reads supporting ALT\">" . "\n";
        print OUTFILE "##FORMAT=<ID=VAQ,Number=1,Type=Float,Description=\"Variant Quality\">" . "\n";

        #INFO
	print OUTFILE "##INFO=<ID=VT,Number=1,Type=String,Description=\"Variant type\">" . "\n";


        #column header:
        print OUTFILE  "#" . join("\t", ("CHROM","POS","ID","REF","ALT","QUAL","FILTER","INFO","FORMAT","$sample_id")) . "\n";
        OUTFILE->close();
    }


#-------------------------------------------
    sub print_body{
        my ($output_file,$snvHash) = @_;

        open(OUTFILE, ">>$output_file") or die "Can't open output file: $!\n";
        my %snvhash = %{$snvHash};

        #sort by chr, start for clean output
        sub keySort{
            my($x,$y) = @_;
            my @x1 = split(":",$x);
            my @y1 = split(":",$y);
            return($x1[0] <=> $y1[0] || $x1[1] <=> $y1[1])
        }
        my @sortedKeys = sort { keySort($a,$b) } keys %snvhash;

        foreach my $key (@sortedKeys){
            my @outline;
            push(@outline, $snvhash{$key}{"chrom"});
            push(@outline, $snvhash{$key}{"pos"});


            #ID
            if (exists($snvhash{$key}{"id"})){
                push(@outline, $snvhash{$key}{"id"});
            } else {
                push(@outline, ".");
            }

            #ref/alt
            push(@outline, $snvhash{$key}{"ref"});
            push(@outline, $snvhash{$key}{"alt"});

            #QUAL
            if (exists($snvhash{$key}{"qual"})){
                push(@outline, $snvhash{$key}{"qual"});
            } else {
                push(@outline, ".");
            }

            #FILTER
            if (exists($snvhash{$key}{"filter"}) && $snvhash{$key}{"filter"} ne ""){
                push(@outline, $snvhash{$key}{"filter"});
            } else {
                push(@outline, "PASS");
            }

            #INFO
            if (exists($snvhash{$key}{"info"})){
                push(@outline, $snvhash{$key}{"info"});
            } else {
                push(@outline, ".");
            }

            #FORMAT
            push(@outline, "GT:GQ:DP:BQ:MQ:AD:FA:VAQ");

            my @format;

            my @fields = ("GT","GQ","DP","BQ","MQ","AD","FA","VAQ");
            #collect format fields
            foreach my $field (@fields){
                if(exists($snvhash{$key}{$field})){
                    push(@format, $snvhash{$key}{$field});
                } else {
                    push(@format,".")
                }

            }
            push(@outline, join(":",@format));

            print OUTFILE join("\t",@outline) . "\n";
        }
    }

    #-----------------------------------------
    # read in the Varscan file

    sub varscanRead{
	my ($varscan_file, $chrom, $type) = @_;
	my %varScanSnvs;

	my $inFh = IO::File->new( "$varscan_file" ) || die "can't open file\n";

	while(my $line = $inFh->getline )
	{
	    chomp($line);
	    my @col = split("\t",$line);

            #skip header line
            next if $col[0] eq "Chrom";

	    #if we do this on a per-chrom process (for huge files)
	    unless ($chrom eq ""){
		next if($col[0] ne $chrom);
	    }

            ## skip positions where the alt is N
            ## todo - figure out why these are in the file in the first place
            next if(($col[3] eq "N") || ($col[4] eq "N"));


            if ($type eq "snv"){
                my $chr = $col[0];
                #replace X and Y for sorting
                $chr = "23" if $col[0] eq "X";
                $chr = "24" if $col[0] eq "Y";
                $chr = "25" if $col[0] eq "MT";
                my $id = $chr . ":" . $col[1] . ":" . $col[2] . ":" . $col[3];

                #skip MT and NT chrs
                #next if $col[0] =~ /^MT/;
                next if $col[0] =~ /^NT/;
                next if $col[0] =~ /random/;

                $varScanSnvs{$id}{"chrom"} = $col[0];
                $varScanSnvs{$id}{"pos"} = $col[1];


                #get all the alleles together (necessary for the GT field)
                my @refAlleles = split(",", convertIub($col[2]));
                my @allAlleles = split(",", convertIub($col[2]));
                my @varAlleles;
                my @tmp = split(",",convertIub($col[3]));

                #only add non-reference alleles to the alt field
                foreach my $alt (@tmp){
                    unless (grep $_ eq $alt, @allAlleles){
                        push(@allAlleles,$alt);
                        push(@varAlleles,$alt);
                    }
                }

                #add ref and alt alleles
                $varScanSnvs{$id}{"ref"} = $col[2];

                # there's an edge case when the ref is not ACGT where no alt will be output,
                # causing VCFtools to choke. deal with it here
                if ((@varAlleles == 0) && ($col[2] !~ /[ACTG]/)){
                    $varScanSnvs{$id}{"ref"} = "N";
                    $varScanSnvs{$id}{"alt"} = convertIub($col[3]);
                    my @arr = (("N"),(split(",",convertIub($col[3]))));
                    $varScanSnvs{$id}{"GT"} = genGT($col[3],@arr);
                } else {
                    $varScanSnvs{$id}{"alt"} = join(",",@varAlleles);
                    $varScanSnvs{$id}{"GT"} = genGT($col[3],@allAlleles);
                }


                #add the ref and alt alleles' positions in the allele array to the GT field
                $varScanSnvs{$id}{"info"} = "VT=SNP";

                my $score;
                #edge case where a score of zero results in "inf"
                if($col[11] == 0){
                    $score = 99;
                } else {
                    $score = sprintf "%.2f", -10*log10($col[12]);
                }

                #genotype quality
                $varScanSnvs{$id}{"GQ"} = ".";

                #total read depth
                $varScanSnvs{$id}{"DP"} = $col[4]+$col[5];

                #avg base quality ref/var
                $varScanSnvs{$id}{"BQ"} =  $col[10];

                #avg mapping quality ref/var
                $varScanSnvs{$id}{"MQ"} =  $col[13];

                #allele depth
                $varScanSnvs{$id}{"AD"} =  $col[5];

                #fa
                $col[6] =~ s/\%// ;
                $varScanSnvs{$id}{"FA"} = $col[6]/100;

                #vaq
                $varScanSnvs{$id}{"VAQ"} = $score;




            } elsif ($type eq "indel"){

                my $chr = $col[0];
                #replace X and Y for sorting
                $chr = "23" if $col[0] eq "X";
                $chr = "24" if $col[0] eq "Y";
                $chr = "25" if $col[0] eq "MT";
                my $id = $chr . ":" . $col[1] . ":" . $col[3] . ":" . $col[4];

                #skip MT and NT chrs
                #next if $col[0] =~ /^MT/;
                next if $col[0] =~ /^NT/;
                next if $col[0] =~ /random/;

                $varScanSnvs{$id}{"chrom"} = $col[0];
                $varScanSnvs{$id}{"pos"} = $col[1];


                #add the preceding base as an anchor position
                my $pbase = getPrecedingBase($col[0],$col[1]-1);
                $varScanSnvs{$id}{"pos"} = $col[1]-1;

                #insertion
                if ($col[3] eq "-"){
                    $varScanSnvs{$id}{"ref"} = $pbase;
                    $varScanSnvs{$id}{"alt"} = $pbase . $col[4];

                    #deletion
                } elsif ($col[4] eq "-"){
                    $varScanSnvs{$id}{"ref"} = $pbase . $col[3];
                    $varScanSnvs{$id}{"alt"} = $pbase;
                    #confusion
                } else {
                    die("this isn't an insertion or deletion - what is it?\n$line");
                }

                $varScanSnvs{$id}{"GT"} = "0/1";

                $varScanSnvs{$id}{"info"} = "VT=INDEL";

                my $score;
                #edge case where a score of zero results in "inf"
                if($col[12] == 0){
                    $score = 99;
                } else {
                    $score = sprintf "%.2f", -10*log10($col[12]);
                }


                #genotype quality
                $varScanSnvs{$id}{"GQ"} = ".";

                #total read depth
                $varScanSnvs{$id}{"DP"} = $col[5]+$col[6];

                #avg base quality ref/var
                $varScanSnvs{$id}{"BQ"} =  $col[11];

                #avg mapping quality ref/var
                $varScanSnvs{$id}{"MQ"} =  $col[14];

                #allele depth
                $varScanSnvs{$id}{"AD"} =  $col[6];

                #fa
                $col[7] =~ s/\%// ;
                $varScanSnvs{$id}{"FA"} = $col[7]/100;

                #vaq
                $varScanSnvs{$id}{"VAQ"} = $score;
            }
	}

	$inFh->close();
	return %varScanSnvs;
    }



#---------------------------------------------
    sub addDbSnp{
        my ($dbsnp_file, $chrom, $allsnvs)= @_;
        my %allSnvs = %{$allsnvs};

        print STDERR "adding dbSNP info - this will take a few minutes\n";
        my $inFh = IO::File->new( $dbsnp_file ) || die "can't open file\n";
        while( my $line = $inFh->getline )
        {
            unless($line =~ /^#/){
                chomp($line);
                my @fields = split("\t",$line);
                
                $fields[1] =~ s/chr//;

                #skip snps on chrs we're not considering
                if($chrom ne ""){
                    next if $fields[1] ne $chrom;
                }

                #replace X and Y for sorting
                my $chr = $fields[1];
                $chr = "23" if $chr eq "X";
                $chr = "24" if $chr eq "Y";


                #ucsc is zero-based, so we adjust
                my @als = split(/\//,$fields[9]);
                my $key;
                if (@als > 1){
                    $key = $chr . ":" . ($fields[2]+1) . ":" . $als[0] . ":" . $als[1];
                } else {
                    $key = $chr . ":" . ($fields[2]+1) . ":" . $als[0];
                }
                #if the line matches this dbsnp position
                if(exists($allSnvs{$key})){
                    # #note the match in the info field
                    # if(exists($allSnvs{$key}{"info"})){
                    #     $allSnvs{$key}{"info"} = $allSnvs{$key}{"info"} . ";";
                    # } else {
                    #     $allSnvs{$key}{"info"} = "";
                    # }
                    # $allSnvs{$key}{"info"} = $allSnvs{$key}{"info"} . "DB";
                        
                    #add to id field
                    if(exists($allSnvs{$key}{"id"})){
                        $allSnvs{$key}{"id"} = $allSnvs{$key}{"id"} . ";";
                    } else {
                        $allSnvs{$key}{"id"} = "";
                    }
                    $allSnvs{$key}{"id"} = $allSnvs{$key}{"id"} . $fields[4];
                    
                    
#			#if the filter shows a pass, remove it and add dbsnp
#			if($allSnvs{$key}->{FILTER} eq "PASS"){
#			    $allSnvs{$key}->{FILTER} = "dbSNP";
#			} else { #add dbsnp to the list
#			    $allSnvs{$key}->{FILTER} = $allSnvs{$key}->{FILTER} . ",dbSNP";
#			}
                    
                }
            }
        }
}



###############################################################################

    #read in the varscan file
    my %varscan_hash = varscanRead($varscan_file, $chrom, $type);
 
    ## add DBsnp labels, if --dbsnp is specified
    if ($dbsnp_file ne ""){
        addDbSnp($dbsnp_file, $chrom, \%varscan_hash)
    }

    # output the headers
    unless ($skip_header){
	print_header($genome_build, $sample_id, $output_file);
    }

    # output the body of the VCF
    print_body($output_file, \%varscan_hash);
    return 1;
}
