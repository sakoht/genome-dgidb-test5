package Genome::Model::Tools::Somatic::TierVariants;

use warnings;
use strict;

use Genome;
use Carp;
use FileHandle;
use Data::Dumper;
use List::Util qw( max );

class Genome::Model::Tools::Somatic::TierVariants{
    is => 'Command',
    has => [
        ucsc_file => {
            is  => 'String',
            doc => 'The output of the ucsc annotation',
        },
        transcript_annotation_file => {
            is  => 'String',
            doc => 'The output of transcript annotation',
        },
        variant_file => {
            is  => 'String',
            doc => 'The list of variants to be tiered',
        },
    ],
};

sub help_brief {
    "tiers variants",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools tier-variants...    
EOS
}

sub help_detail {                           
    return <<EOS 
tiers variants 
EOS
}

sub execute {
    my $self = shift;

    my $ucsc_file = $self->ucsc_file;
    my $transcript_annotation_file = $self->transcript_annotation_file;
    my $variant_file = $self->variant_file;

    # Open filehandles of plenty
    my $trans_anno_fh = new FileHandle;
    $trans_anno_fh->open($transcript_annotation_file,"r") or croak "Couldn't open $transcript_annotation_file";

    my $ucsc_fh = new FileHandle;
    $ucsc_fh->open($ucsc_file,"r") or croak "Couldn't open $ucsc_file";

    my $variant_fh = new FileHandle;
    $variant_fh->open($variant_file,"r") or croak "Couldn't open $variant_file";

    my $tier1 = new FileHandle;
    $tier1->open($variant_file.".tier1","w") or croak "Couldn't write tier1 file";

    my $tier2 = new FileHandle;
    $tier2->open($variant_file.".tier2","w") or croak "Couldn't write tier2 file";

    my $tier3 = new FileHandle;
    $tier3->open($variant_file.".tier3","w") or croak "Couldn't write tier3 file";

    my $tier4 = new FileHandle;
    $tier4->open($variant_file.".tier4","w") or croak "Couldn't write tier4 file";

    my $tier5 = new FileHandle;
    $tier5->open($variant_file.".tier5","w") or croak "Couldn't write tier5 file";

    my %exonic_at;
    my %variant_at;
    
    while(my $line = $trans_anno_fh->getline) {
        chomp $line;

        my @columns = split ',', $line;

        my ($chr, $start, $stop, $allele1, $allele2, $class, $gene, $transcript, $type, $aa_string) = @columns;
        $type = lc($type);
        if(defined($type) && ($type eq 'silent' || $type eq 'splice_site_del' || $type eq 'splice_site_ins' || $type eq 'in_frame_del' || $type eq 'frame_shift_del' || $type eq 'rna' || $type eq 'frame_shift_ins' || $type eq 'in_frame_ins'|| $type eq 'missense'|| $type eq 'nonsense'|| $type eq 'nonstop'|| $type eq 'splice_site')) {
            $exonic_at{$chr}{$start}{$stop}{$allele1}{$allele2} = join "\t", @columns;
        }
    }

    while(my $line = $variant_fh->getline) {
        chomp $line;
        # DETERMINE TYPE HERE TODO
        my $type = $self->infer_variant_type_from_line ($line);

        if ($type =~ /del|ins/i) {
            my %indel1;
            my %indel2;
            my ($chr,
                $start_pos,
                $star, 
                $somatic_score,
            );
            ($chr,
                $start_pos,
                $star, 
                $somatic_score,
                $indel1{'sequence'},
                $indel2{'sequence'}, 
                $indel1{'length'},
                $indel2{'length'},
            ) = split /\s+/, $line; 
            my @indels;
            push(@indels, \%indel1);
            push(@indels, \%indel2);
            for my $indel(@indels) {

                if ($indel->{'sequence'} eq '*') { next; }
                my $hash;
                my $stop_pos;
                my $start;
                if($indel->{'length'} < 0) {
                    #it's a deletion!
                    $hash->{variation_type}='DEL';
                    $start= $start_pos+1;
                    $stop_pos = $start_pos + abs($indel->{'length'});
                    $hash->{reference}=$indel->{'sequence'};
                    $hash->{variant}=0;
                }
                else {
                    #it's an insertion
                    $hash->{variation_type}='INS';
                    $start=$start_pos;
                    $stop_pos = $start_pos+1;
                    $hash->{reference}=0;
                    $hash->{variant}=$indel->{'sequence'};

                }
                if(exists($exonic_at{$chr}{$start}{$stop_pos}{$hash->{reference}}{$hash->{variant}})) {
                    if($exonic_at{$chr}{$start}{$stop_pos}{$hash->{reference}}{$hash->{variant}} eq 'silent') {
                        print $tier2 $line,"\t",$exonic_at{$chr}{$start}{$stop_pos}{$hash->{reference}}{$hash->{variant}},"\n"; #not gonna happen
                    }
                    else {
                        print $tier1 $line,"\t",$exonic_at{$chr}{$start}{$stop_pos}{$hash->{reference}}{$hash->{variant}}, "\n";
                    }
                    next;
                }
                $variant_at{$chr}{$start}{$stop_pos}{$hash->{reference}}{$hash->{variant}} = $line;
            }
        } elsif ($type =~ /snp/i) {
            my ($chr, $start, $somatic_score, $reference, $variant) = split /\t/, $line;
            my $stop = $start;
            if(exists($exonic_at{$chr}{$start}{$stop}{$reference}{$variant})) {
                if($exonic_at{$chr}{$start}{$stop}{$reference}{$variant} eq 'silent') {
                    print $tier2 $line, "\n";
                }
                else {
                    print $tier1 $line, "\n";
                }
                next; #skip
            }
            $variant_at{$chr}{$start}{$stop}{$reference}{$variant} = $line;
        } else {
            $self->error_message("Type $type not implemented");
            return;
        }
    }

    my %totals;
    while(my $line = $ucsc_fh->getline) {
        chomp $line;
        my @fields = split /\t/, $line;
        map { $_ ='' if($_ eq '-')} @fields;
        my ( $chr,$start,$stop,
            $decodeMarshfield, #recombination rates
            $repeatMasker,
            $selfChain,
            $cnpLocke,
            $cnpSebat2,
            $cnpSharp2,
            $cpgIslandExt,
            $delConrad2,
            $dgv,
            $eponine,
            $firstEF,
            $gad, #disease associations
            $genomicSuperDups,
            $microsat,
            $phastConsElements17way,
            $phastConsElements28way,
            $polyaDb,
            $polyaPredict,
            $simpleRepeat,
            $switchDbTss,
            $targetScanS,
            $tfbsConsSites,
            $vistaEnhancers,
            $wgEncodeGisChipPet,
            $wgEncodeGisChipPetHes3H3K4me3,
            $wgEncodeGisChipPetMycP493,
            $wgEncodeGisChipPetStat1Gif,
            $wgEncodeGisChipPetStat1NoGif,
            $cnpIafrate2,
            $cnpRedon,
            $cnpTuzun,
            $delHinds2,
            $delMccarroll,
            $encodeUViennaRnaz,
            $exaptedRepeats,
            $laminB1,
            $oreganno,
            $regPotential7X,
            $uppsalaChipH3acSignal,
            $uppsalaChipUsf1Signal,
            $uppsalaChipUsf2Signal,
            $wgEncodeUcsdNgTaf1Signal,
            $wgEncodeUcsdNgTaf1ValidH3K4me,
            $wgEncodeUcsdNgTaf1ValidH3ac,
            $wgEncodeUcsdNgTaf1ValidRnap,
            $wgEncodeUcsdNgTaf1ValidTaf,
            $knownGenes,
            $HUGO,) = @fields; 

        if(exists($variant_at{$chr}{$start}{$stop})) {
            #check selfChain and repeatMAsker to filter out crap that is unlikely to validate
            #if($selfChain && max(split /\s/, $selfChain) > 0 && $repeatMasker =~ /^(Simple_repeat|Satellite)/) {
            #    print $tier5 $variant_at{$chr}{$start}{$stop}, "\n";
            #}
            #Tier1 exonic genes were printed when the snp file was read in
            #
            #Tier2 Conserved Blocks
            if(($phastConsElements28way && $phastConsElements28way >= 500) || ($phastConsElements17way && $phastConsElements17way >= 500)) {
                for my $reference (keys %{$variant_at{$chr}{$start}{$stop}}) {
                    for my $variant(keys %{$variant_at{$chr}{$start}{$stop}{$reference}}) {
                        print $tier2 $variant_at{$chr}{$start}{$stop}{$reference}{$variant}, "\n";
                    }
                }
            }
            elsif($repeatMasker || $microsat || $simpleRepeat || $exaptedRepeats) {
                #Tier 5 repeats everything else!!!
                for my $reference (keys %{$variant_at{$chr}{$start}{$stop}}) {
                    for my $variant(keys %{$variant_at{$chr}{$start}{$stop}{$reference}}) {
                        print $tier5 $variant_at{$chr}{$start}{$stop}{$reference}{$variant}, "\n";
                    }
                }
            }
            elsif($targetScanS || $oreganno || $tfbsConsSites || $vistaEnhancers || $eponine || $firstEF 
                || $wgEncodeUcsdNgTaf1ValidTaf 
                #|| $wgEncodeGisChipPet 
                #|| $wgEncodeGisChipPetHes3H3K4me3 
                #|| $wgEncodeGisChipPetMycP493 
                #|| $wgEncodeGisChipPetStat1Gif 
                #|| $wgEncodeGisChipPetStat1NoGif 
                #|| $wgEncodeUcsdNgTaf1Signal 
                || $wgEncodeUcsdNgTaf1ValidRnap 
                || $wgEncodeUcsdNgTaf1ValidH3ac 
                || $wgEncodeUcsdNgTaf1ValidH3K4me 
                #|| $regPotential7X 
                    || $polyaPredict || $polyaDb || $switchDbTss 
                    #|| $uppsalaChipUsf2Signal || $uppsalaChipUsf1Signal || $uppsalaChipH3acSignal 
                    || $encodeUViennaRnaz || $laminB1 || $cpgIslandExt) {
                my %reg_hash;
                @reg_hash{('targetScanS','oreganno','tfbsConsSites','vistaEnhancers','eponine','firstEF','wgEncodeUcsdNgTaf1ValidTaf','wgEncodeGisChipPet','wgEncodeGisChipPetHes3H3K4me3','wgEncodeGisChipPetMycP493','wgEncodeGisChipPetStat1Gif','wgEncodeGisChipPetStat1NoGif','wgEncodeUcsdNgTaf1Signal','wgEncodeUcsdNgTaf1ValidRnap','wgEncodeUcsdNgTaf1ValidH3ac','wgEncodeUcsdNgTaf1ValidH3K4me','regPotential7X','polyaPredict','polyaDb','switchDbTss','uppsalaChipUsf2Signal','uppsalaChipUsf1Signal','uppsalaChipH3acSignal','encodeUViennaRnaz','laminB1','cpgIslandExt')} = ($targetScanS,$oreganno,$tfbsConsSites,$vistaEnhancers,$eponine,$firstEF,$wgEncodeUcsdNgTaf1ValidTaf,$wgEncodeGisChipPet,$wgEncodeGisChipPetHes3H3K4me3,$wgEncodeGisChipPetMycP493,$wgEncodeGisChipPetStat1Gif,$wgEncodeGisChipPetStat1NoGif,$wgEncodeUcsdNgTaf1Signal,$wgEncodeUcsdNgTaf1ValidRnap,$wgEncodeUcsdNgTaf1ValidH3ac,$wgEncodeUcsdNgTaf1ValidH3K4me,$regPotential7X,$polyaPredict,$polyaDb,$switchDbTss,$uppsalaChipUsf2Signal,$uppsalaChipUsf1Signal,$uppsalaChipH3acSignal,$encodeUViennaRnaz,$laminB1,$cpgIslandExt);
                foreach my $col (keys %reg_hash) {
                    if($reg_hash{$col}) {
                        $totals{$col} += 1;
                    }
                }
                #TIER3 Regulatory regions
                for my $reference (keys %{$variant_at{$chr}{$start}{$stop}}) {
                    for my $variant(keys %{$variant_at{$chr}{$start}{$stop}{$reference}}) {
                        print $tier3 $variant_at{$chr}{$start}{$stop}{$reference}{$variant}, "\n";
                    }
                }

            }
            else {
                #Tier 5 repeats everything else!!!
                for my $reference (keys %{$variant_at{$chr}{$start}{$stop}}) {
                    for my $variant(keys %{$variant_at{$chr}{$start}{$stop}{$reference}}) {
                        print $tier4 $variant_at{$chr}{$start}{$stop}{$reference}{$variant}, "\n";
                    }
                }
            }

        }
    }

    foreach my $col (keys %totals) {
        print STDOUT "$col: ",$totals{$col},"\n";
    }
}

sub infer_variant_type_from_line {
    my $self = shift;
    my $line = shift;

    # FIXME ... totally need a better method here but indels have stars in the lines
    if ($line =~ m/\*/) {
        my @columns = split "\t", $line;

        my ($reference, $variant) = @columns[6,7];

        if (($reference eq '-')||($reference eq '0')) {
            return 'INS';
        } elsif (($variant eq '-')||($variant eq '0')) {
            return 'DEL';
        } else {
            $self->error_message("Could not determine variant type from variant:");
            $self->error_message(Dumper($variant));
            die;
        }
    } else {
        return 'SNP';
    }
}
