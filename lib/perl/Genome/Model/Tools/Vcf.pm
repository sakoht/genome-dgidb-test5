package Genome::Model::Tools::Vcf;

use strict;
use warnings;

use Genome;

#This is the variable to change if you wish to change the version of all vcf files being created
# 3 was incremented to 4 because of a bug in VcfFilter.pm. When filtered twice, FT fields were being wiped out rather than propagated from "FILTER".
my $VCF_VERSION = "4";

class Genome::Model::Tools::Vcf {
    is => ['Command'],
    has => [
        vcf_version => {
            is => 'Text',
            default => $VCF_VERSION,
        },
    ],
};

sub get_vcf_version {
    return $VCF_VERSION;
}

sub help_brief {
    "Tools and scripts to create and manipulate VCF files."
}

sub help_detail {
    return <<EOS
Tools and scripts to create and manipulate VCF files.
EOS
}

1;
