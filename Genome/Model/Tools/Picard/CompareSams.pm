package Genome::Model::Tools::Picard::CompareSams;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Picard::CompareSams {
    is  => 'Genome::Model::Tools::Picard',
    has_input => [
        input_file_1 => {
            is  => 'String',
            doc => 'The first SAM file path to compare.',
        },
        input_file_2 => {
            is  => 'String',
            doc => 'The second SAM file path to compare.',
        },
        output_file => {
            is => 'String',
            doc => 'The path to the output file.',
        },
    ],
};

sub help_brief {
    'Tool to compare a BAM or SAM file using Picard';
}

sub help_detail {
    return <<EOS
    Tool to compare a BAM or SAM file using Picard.  For Picard documentation of this command see:
    http://picard.sourceforge.net/command-line-overview.shtml#CompareSams
EOS
}

sub execute {
    my $self = shift;

    my $jar_path = $self->picard_path .'/CompareSAMs.jar';
    unless (-e $jar_path) {
        die('Failed to find '. $jar_path .'!  This command may not be available in version '. $self->use_version);
    }
    my $input_file_1 = $self->input_file_1;
    my $input_file_2 = $self->input_file_2;
    my $cmp_cmd = $jar_path .' net.sf.samtools.apps.CompareSAMs '. $input_file_1 .' '. $input_file_2 .' > '. $self->output_file;
    $self->run_java_vm(
        cmd => $cmp_cmd,
        input_files => [$input_file_1,$input_file_2],
        output_files => [$self->output_file],
        skip_if_output_is_present => 0,
    );
    return 1;
}


1;
