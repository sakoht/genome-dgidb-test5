package Genome::InstrumentData::Command::Dump;

#REVIEW fdu 11/17/2009
#Dumpping sequence files from other platforms like 454 and Sanger reads should be implemented too.

use strict;
use warnings;

use Genome;
use Cwd;

class Genome::InstrumentData::Command::Dump {
    is => 'Genome::InstrumentData::Command',
    has => [
            directory => {
                          is => 'Text',
                          doc => 'directory to dump instrument data(defaults to current working directory)',
                          default_value => getcwd(),
                      },
        ],
};

sub execute {
    my $self = shift;

    unless (Genome::Utility::FileSystem->validate_directory_for_write_access($self->directory)) {
        $self->error_message('Failed to validate directory '. $self->directory .' for write access!');
        die($self->error_message);
    }

    my $instrument_data = $self->instrument_data;
    if ($instrument_data->sequencing_platform eq 'solexa') {
        my $directory = $instrument_data->dump_illumina_fastq_archive($self->directory);
        $self->status_message("Finished dumping data to '$directory'");
    } else {
        $self->error_message('This command '. $self->command_name .' has not been implemented for '. $instrument_data->sequencing_platform .' instrument data!');
        die($self->error_message);
    }
    return 1;
}
