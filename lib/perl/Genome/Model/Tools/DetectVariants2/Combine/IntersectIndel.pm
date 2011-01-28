package Genome::Model::Tools::DetectVariants2::Combine::IntersectIndel;

use warnings;
use strict;

use Genome;

class Genome::Model::Tools::DetectVariants2::Combine::IntersectIndel{
    is => 'Genome::Model::Tools::DetectVariants2::Combine',
};


sub help_brief {
    "Intersect two indel variant bed files",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
gmt detect-variants combine intersect-indel --variant-file-a samtools.hq.v1.bed --variant-file-b varscan.hq.v1.bed --output-file 
EOS
}

sub help_detail {                           
    return <<EOS 
EOS
}

sub _combine_variants {
    my $self = shift;
    
    ### TODO This currently does NOT intersect indels, but merely passes on those from variant_file_a

    my $cmd = "cp ".$self->variant_file_a." ".$self->output_file;
    my $result = Genome::Sys->shellcmd( cmd => $cmd);
    return 1;
}

1;
