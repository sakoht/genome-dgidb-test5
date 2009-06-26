package Genome::Model::Tools::Sv::Yenta;

use strict;
use warnings;

use Genome;
use Command;
use IO::File;

class Genome::Model::Tools::Sv::Yenta {
    is => 'Command',
    has => [
    breakdancer_file => 
    { 
        type => 'String',
        is_optional => 0,
        doc => "Input file of breakdancer output for a single individual",
    },
    output_dir =>
    {
        type => 'String',
        is_optional => 0,
        doc => "Output directory name for placement of directories",
    },        
    tumor_model_map_file_prefix =>
    {
        type => 'String',
        is_optional => 0,
        doc => "map file location and prefix for tumor",
    },
    normal_model_map_file_prefix =>
    {
        type => 'String',
        is_optional => 0,
        doc => "map file location and prefix for normal",
    },
    types => {
        type => 'String',
        is_optional => 1,
        doc => "Comma separated string of types to graph",
        default => "INV,INS,DEL,ITX,CTX",
    },
    possible_BD_type => {
        type => 'hashref',
        doc => "hashref of possible BreakDancer SV types",
        is_optional => 1,
        default => {INV => 1,INS => 1,DEL => 1,ITX => 1,CTX => 1,},
    },
    yenta_program => {
        type => "String",
        default => "/gscuser/dlarson/yenta/trunk/src/yenta.long",
        doc => "executable of yenta to use", 
        is_optional => 1,
    },

    ],
};


sub execute {
    my $self=shift;
    $DB::single = 1; 

    #Not allowed to store hash in UR?
    
    my @types = map { uc $_ } split /,/, $self->types;
    my $allowed_types = $self->possible_BD_type;
    foreach my $type (@types) {
        unless(exists($allowed_types->{$type})) {
            $self->error_message("$type type is not a valid BreakDancer SV type");
            return;
        }
    }
    my %types = map {$_ => 1} @types; #create types hash
    
    
    unless(-f $self->breakdancer_file) {
        $self->error_message("breakdancer file is not a file: " . $self->breakdancer_file);
        return;
    }

    my $indel_fh = IO::File->new($self->breakdancer_file);
    unless($indel_fh) {
        $self->error_message("Failed to open filehandle for: " .  $self->breakdancer_file );
        return;
    }

    my $TUMOR_SUBMAP_PATH = $self->tumor_model_map_file_prefix;
    my $NORMAL_SUBMAP_PATH = $self->normal_model_map_file_prefix;
    my $output_dir = $self->output_dir;

    my $grapher = $self->yenta_program;
    my $count = 0;
    #assuming we are reasonably sorted
    while ( my $line = $indel_fh->getline) {
        chomp $line;
        #$self->status_message("(SEARCHING FOR: $line)");
        my ($chr1,
            $chr1_pos,
            $orientation1,
            $chr2,
            $chr2_pos,
            $orientation2,
            $type,
            $size,
        ) = split /\s+/, $line; 
        if(exists($types{$type})) {
            $count++;
            #then we should graph it
            #submit the job
            #Doing this based on chromosomes in case types ever change
            if($chr1 eq $chr2) {
                my $name = "$output_dir/${chr1}_${chr1_pos}_${chr2}_${chr2_pos}_Tumor_${type}.q1.png";
                system("bsub -R 'select[type==LINUX64]' -eo $name.err -oo $name.out '$grapher -q 1 -b 500 -o $name $TUMOR_SUBMAP_PATH$chr1.map $chr1 $chr1_pos $chr2_pos'");
                $name = "$output_dir/${chr1}_${chr1_pos}_${chr2}_${chr2_pos}_Normal_${type}.q1.png";
                system("bsub -R 'select[type==LINUX64]' -eo $name.err -oo $name.out '$grapher -q 1 -b 500  -o $name $NORMAL_SUBMAP_PATH$chr1.map $chr1 $chr1_pos $chr2_pos'");
                $name = "$output_dir/${chr1}_${chr1_pos}_${chr2}_${chr2_pos}_Tumor_${type}.q0.png";
                system("bsub -R 'select[type==LINUX64]' -eo $name.err -oo $name.out '$grapher -q 0 -b 500  -o $name $TUMOR_SUBMAP_PATH$chr1.map $chr1 $chr1_pos $chr2_pos'");
                $name = "$output_dir/${chr1}_${chr1_pos}_${chr2}_${chr2_pos}_Normal_${type}.q0.png";
                system("bsub -R 'select[type==LINUX64]' -eo $name.err -oo $name.out '$grapher -q 0 -b 500  -o $name $NORMAL_SUBMAP_PATH$chr1.map $chr1 $chr1_pos $chr2_pos'");
            }
            else {
                my $name = "$output_dir/${chr1}_${chr1_pos}_${chr2}_${chr2_pos}_Tumor_${type}.q1.png";
                system("bsub -R 'select[type==LINUX64]' -eo $name.err -oo $name.out '$grapher -q 1 -b 500 -o $name $TUMOR_SUBMAP_PATH$chr1.map $chr1 $chr1_pos $chr1_pos $TUMOR_SUBMAP_PATH$chr2.map $chr2 $chr2_pos $chr2_pos'");
                $name = "$output_dir/${chr1}_${chr1_pos}_${chr2}_${chr2_pos}_Normal_${type}.q1.png";
                system("bsub -R 'select[type==LINUX64]' -eo $name.err -oo $name.out '$grapher -q 1 -b 500  -o $name $NORMAL_SUBMAP_PATH$chr1.map $chr1 $chr1_pos $chr1_pos $NORMAL_SUBMAP_PATH$chr2.map $chr2 $chr2_pos $chr2_pos'");
                $name = "$output_dir/${chr1}_${chr1_pos}_${chr2}_${chr2_pos}_Tumor_${type}.q0.png";
                system("bsub -R 'select[type==LINUX64]' -eo $name.err -oo $name.out '$grapher -q 0 -b 500  -o $name $TUMOR_SUBMAP_PATH$chr1.map $chr1 $chr1_pos $chr1_pos $TUMOR_SUBMAP_PATH$chr2.map $chr2 $chr2_pos $chr2_pos'");
                $name = "$output_dir/${chr1}_${chr1_pos}_${chr2}_${chr2_pos}_Normal_${type}.q0.png";
                system("bsub -R 'select[type==LINUX64]' -eo $name.err -oo $name.out '$grapher -q 0 -b 500  -o $name $NORMAL_SUBMAP_PATH$chr1.map $chr1 $chr1_pos $chr1_pos $NORMAL_SUBMAP_PATH$chr2.map $chr2 $chr2_pos $chr2_pos'");

            }
            if($count % 25 == 0) {
                sleep(600); #delay by 10 minutes before rolling out the next 50
            }

        }
            
    }

    $indel_fh->close; 

    return 1;
}

1;

sub help_detail {
    my $help = <<HELP;
Ken Chen's BreakDancer predicts large structural variations by examining read pairs. This module uses the yenta program to graph read pairs for a given set of regions. yenta operates by scanning a maq map file for reads in the regions and matches up pairs across those regions. The output consists of a set of tracks for each region. One track is the read depth across the region (excluding gapped reads) the other is a so called barcode output. For multiple regions, the regions are displayed in order listed in the filename. Read depth tracks first, then the barcode graphs. Reads are represented as lines and pairs are joined by arcs. These are color coded by abnormal read pair type as follows:

Mapping status                                      Color
Forward-Reverse, abnormal insert size               magenta
Forward-Forward                                     red
Reverse-Reverse                                     blue
Reverse-Forward                                     green
One read unmapped                                   yellow
One read mapped to a different chromosome           cyan

Yenta.pm generates 4 PNG images for each predicted SV, 2 for tumor and 2 for normal. There is a q0 file showing reads of all mapping qualities and a q1 file showing reads of mapping quality 1 or more. A maq mapping quality of zero indicates a repeat region that mapped multiple places in the genome equally well.

The naming convention of the files produced is as follows:
chr_pos_chr_pos_tumor/normal_type.q#.png

HELP

}

sub help_brief {
    return "This module takes a breakdancer file and uses the rudimentary graphical tool yenta to graph the read pairs.";
}


