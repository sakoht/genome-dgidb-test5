package Genome::Model::Tools::Bed::Convert::Snv::SniperToBed;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Bed::Convert::Snv::SniperToBed {
    is => ['Genome::Model::Tools::Bed::Convert::Snv'],
};

sub help_brief {
    "Tools to convert sniper SNV format to BED.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
  gmt bed convert snv sniper-to-bed --source snps_all_sequences --output snps_all_sequences.bed
EOS
}

sub help_detail {                           
    return <<EOS
    This is a small tool to take SNV calls in sniper format and convert them to a common BED format (using the first four columns).
EOS
}

sub process_source {
    my $self = shift;
    
    my $input_fh = $self->_input_fh;
    
    while(my $line = <$input_fh>) {
        my ($chromosome, $position, $reference, $genotype, @extra) = split("\t", $line);
        
        #position => 1-based position of the SNV
        #BED uses 0-based position of and after the event
        $self->write_bed_line($chromosome, $position - 1, $position, $reference, $genotype);
    }
    
    return 1;
}

1;
