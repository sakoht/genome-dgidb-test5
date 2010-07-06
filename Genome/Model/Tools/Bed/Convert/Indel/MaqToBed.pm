package Genome::Model::Tools::Bed::Convert::Indel::MaqToBed;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Bed::Convert::Indel::MaqToBed {
    is => ['Genome::Model::Tools::Bed::Convert::Indel'],
};

sub help_brief {
    "Tools to convert MAQ indel format to BED.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
  gmt bed convert indel maq-to-bed --source indelpe.out --output indels_all_sequences.bed
EOS
}

sub help_detail {                           
    return <<EOS
    This is a small tool to take indel calls in MAQ format and convert them to a common BED format (using the first four columns).
EOS
}

sub process_source {
    my $self = shift;
    
    my $input_fh = $self->_input_fh;
    
    for my $line (<$input_fh>) {
        my ($chromosome, $position, $quality, $_num_reads_across, $length, $bases, @extra) = split(/[\t:]/, $line);
        
        unless($quality =~ m/[*+-.]/) {
            $self->error_message('The file does not appear to be the output from `maq indelpe`. (Encountered unexpected quality value: ' . $quality . ') This converter does not support `maq indelsoa` output.');
            return;
        }
        
        my ($minus) = $length =~ s/-//;
        
        my ($reference, $variant, $start, $stop);
        
        $start = $position - 1;
        
        if($minus) {
            $reference = $bases;
            $variant = '*';
            $stop = $start + $length;
        } else {
            $reference = '*';
            $variant = $bases;
            $stop = $start + 2; #Two positions are included--the base preceding and the base following the insertion event
        }
        
        $self->write_bed_line($chromosome, $start, $stop, $reference, $variant);
    }
    
    return 1;
}

1;
