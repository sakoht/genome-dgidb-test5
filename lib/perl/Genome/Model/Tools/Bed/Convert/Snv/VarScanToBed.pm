package Genome::Model::Tools::Bed::Convert::Snv::VarScanToBed;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Bed::Convert::Snv::VarScanToBed {
    is => ['Genome::Model::Tools::Bed::Convert::Snv'],
};

sub help_brief {
    "Tools to convert var-scan SNV format to BED.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
  gmt bed convert snv var-scan-to-bed --source snps_all_sequences --output snps_all_sequences.bed
EOS
}

sub help_detail {                           
    return <<EOS
    This is a small tool to take SNV calls in var-scan format and convert them to a common BED format (using the first four columns).
EOS
}

sub process_source {
    my $self = shift;
    
    my $input_fh = $self->_input_fh;
    
    while(my $line = <$input_fh>) {
        my ($chromosome, $position, $reference, $consensus, @extra) = split("\t", $line);
        
        no warnings qw(numeric);
        next unless $position eq int($position); #Skip header line(s)
        use warnings qw(numeric);
        
        #position => 1-based position of the SNV
        #BED uses 0-based position of and after the event
        $self->write_bed_line($chromosome, $position - 1, $position, $reference, $consensus);
    }
    
    return 1;
}

1;
