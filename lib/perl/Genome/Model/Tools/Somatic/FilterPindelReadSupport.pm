package Genome::Model::Tools::Somatic::FilterPindelReadSupport;

use warnings;
use strict;

use Genome;
use Carp;
use IO::File;

class Genome::Model::Tools::Somatic::FilterPindelReadSupport{
    is => 'Command',
    has => [
        read_support_file => {
            is  => 'String',
            is_input  => 1,
            is_optional => 0,
            doc => 'The pindel indels_all_sequences.bed.tier?.read_support file.',
        },
        output_file => {
            is => 'Text',
            is_input => 1,
            is_output => 1,
            is_optional => 0,
            doc => "Variants that have successfully passed the Pindel Read Support filter"
        },
        filter_dbsnp => {
            is => 'Boolean',
            is_optional => 1,
            is_input => 1,
            default => 1,
            doc => 'Boolean parameter which specifies whether or not to remove dbsnp matches.',
        },
        var_to_ref_read_ratio => {
            is => 'String',
            is_optional => 1,
            is_input => 1,
            default => '0.2',
            doc => 'This ratio determines what ratio of variant supporting reads to reference supporting reads to allow',
        },
        remove_single_stranded => {
            is => 'Boolean',
            is_optional => 1,
            is_input => 1,
            default => 1,
            doc => 'enable this to filter out variants which have exclusively pos or neg strand supporting reads.',
        },
        skip_if_output_present => {
            is => 'Boolean',
            is_optional => 1,
            is_input => 1,
            default => 0,
            doc => 'enable this flag to shortcut through annotation if the output_file is already present. Useful for pipelines.',
        },
    ],
};

sub help_brief {
    "Filter indels on read support stats",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
gmt somatic filter-pindel-read-support --read-support-file /my/read/support.bed.tier1.read_support --output-file /my/homedire/outputfile.bed  
EOS
}


sub execute {
    my $self = shift;

    unless(-e $self->read_support_file) {
        $self->error_message($self->read_support_file . " is not found or is empty.");
        die $self->error_message;
    }
    if(-e $self->output_file && $self->skip_if_output_present) {
        $self->status_message("Found output file at ".$self->output_file." shortcutting past filer.");
        return 1;
    }
    my $input = Genome::Utility::FileSystem->open_file_for_reading( $self->read_support_file );
    my $output = Genome::Utility::FileSystem->open_file_for_writing( $self->output_file );
    $input->getline;  # throw out header line
    while( my $line = $input->getline){
        chomp $line;
        my ($chr,$start,$stop,$refvar,$is,$rs,$ps,$dbsnp) = split "\t", $line;
        if(($self->filter_dbsnp)&&($dbsnp eq '-')){

            if(($rs==0)||($is/$rs) > $self->var_to_ref_read_ratio){
                my $display=undef;
                if($self->remove_single_stranded){
                    if(($ps != 1)&&($ps !=0)){
                        $display=1;
                    }
                }
                else {
                    $display=1;
                }
                if($display){
                    print $output join("\t", ($chr,$start,$stop,$refvar,$is,$rs,$ps))."\n";
                }
            }
        }
    }

    $input->close;

    return 1;
}

1;
