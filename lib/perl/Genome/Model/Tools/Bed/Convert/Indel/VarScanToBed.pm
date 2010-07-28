package Genome::Model::Tools::Bed::Convert::Indel::VarScanToBed;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Bed::Convert::Indel::VarScanToBed {
    is => ['Genome::Model::Tools::Bed::Convert::Indel'],
};

sub help_brief {
    "Tools to convert var-scan indel format to BED.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
  gmt bed convert indel var-scan-to-bed --source indels_all_sequences --output indels_all_sequences.bed
EOS
}

sub help_detail {                           
    return <<EOS
    This is a small tool to take indel calls in var-scan format and convert them to a common BED format (using the first four columns).
EOS
}

sub process_source {
    my $self = shift;
    
    my $input_fh = $self->_input_fh;
    
    while(my $line = <$input_fh>) {
        my ($chromosome, $position, $_reference, $consensus, @extra) = split("\t", $line);
        
        no warnings qw(numeric);
        next unless $position eq int($position); #Skip header line(s)
        use warnings qw(numeric);
        
        my ($indel_call_1, $indel_call_2) = split('/', $consensus);
        
        if($indel_call_1 eq $indel_call_2) {
            undef $indel_call_2;
        }

        for my $indel ($indel_call_1, $indel_call_2) {
            next unless defined $indel;
            next if $indel eq '*'; #Indicates only one indel call...and this isn't it!
            
            #position => 1-based position of the start of the indel
            #BED uses 0-based position of and after the event
        
            my ($reference, $variant, $start, $stop);
            
            $start = $position - 1; #Convert to 0-based coordinate
            
            if(substr($indel,0,1) eq '+') {
                $reference = '*';
                $variant = substr($indel,1);
                $stop = $start + 2; #Two positions are included--the base preceding and the base following the insertion event
            } elsif(substr($indel,0,1) eq '-') {
                $start += 1; #varscan reports the position before the first deleted base
                $reference = substr($indel,1);
                $variant = '*';
                $stop = $start + length($reference);
            } else {
                $self->error_message('Unexpected indel format encountered: ' . $indel);
                return;
            }
        
            $self->write_bed_line($chromosome, $start, $stop, $reference, $variant);
        }
    }
    
    return 1;
}

1;
