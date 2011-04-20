package Genome::Model::Tools::FastQual;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
require File::Basename;
require Genome::Utility::IO::StdinRefReader;
require Genome::Utility::IO::StdoutRefWriter;

class Genome::Model::Tools::FastQual {
    is  => 'Command',
    has => [
        input => {
            is => 'Text',
            is_many => 1,
            is_optional => 1,
            doc => 'Input files, "-" to read from STDIN or undefined if piping between fast-qual commands. If multiple files are given for fastq types (sanger), one sequence will be read from each file and then handled as a set. If multiple files are given for type phred (fasta), the first file should be the sequences, and the optional second file should be the qualities. Do not use this option when piping between fast-qual commands.',
        }, 
        _input_to_string => {
            calculate => q| 
                my @input = $self->input;
                return 'PIPE' if not @input;
                return 'STDin' if $input[0] eq '-';
                return join(',', @input);
            |,
        },
        type_in => {
            is  => 'Text',
            valid_values => [ valid_types() ],
            is_optional => 1,
            doc => 'The sequence and quality type for the input. Optional for files, and if not given, will be based on the extension of the first file (.fastq => sanger | .fasta .fna .fa => phred). Required for reading from STDIN. Do not use this option when piping between fast-qual commands.',
        },
        paired_input => {
            is => 'Boolean',
            is_optional => 1,
            doc => "FASTQ: If giving one input, read two sequences at a time. If two inputs are given, a sequence will be read from each.\nPHRED: NA",
        },
        output => {
            is => 'Text',
            is_many => 1,
            is_optional => 1,
            doc => 'Output files, "-" to write to STDOUT or undefined if piping between fast-qual commands.  Optional for files, and if not given, will be based on the extension of the first file (.fastq => sanger  .fasta .fna .fa => phred). Do not use this option when piping between fast-qual commands. ',
        },
        _output_to_string => {
            calculate => q| 
                my @output = $self->output;
                return 'PIPE' if not @output;
                return 'STDOUT' if $output[0] eq '-';
                return join(',', @output);
            |,
        },
        type_out => {
            is  => 'Text',
            valid_values => [ valid_types() ],
            is_optional => 1,
            doc => 'The sequence and quality type for the output. Optional for files, and if not given, will be based on the extension of the first file (.fastq => sanger | .fasta .fna .fa => phred). Defaults to sanger (fastq) for writing to STDOUT. Do not use this option when piping between fast-qual commands.',
        },
        paired_output => {
            is => 'Boolean',
            is_optional => 1,
            doc => "FASTQ: If giving one output, only write valid pairs. If given two outputs, write valid pairs to the first, singletons to the second. If given three outputs, foreard will be written to the first, reverse to the second and singletons (valid one from pair) to the third.\nPHRED: NA",
        },
        metrics_file_out => {
            is => 'Text',
            is_optional => 1,
            doc => 'Output sequence metrics for the output to this file. Current metrics include: count, bases',
        },
        _reader => { is_optional => 1, },
        _writer => { is_optional => 1, },
    ],
};

sub help_brief {
    return <<HELP
    Transform sequences
HELP
}

sub help_detail {
    return <<HELP 
    Transform sequences. See sub-commands for a variety of functionality.

    Types Handled
    * sanger (fastq)
    * phred (fasta/quality)
    
    Things This Base Command Can Do
    * collate two inputs into one (sanger only)
    * decollate one input into two (sanger only)
    * convert type
    * remove quality fastq headers
    
    Things This Base Command Can Not Do
    * be used in a pipe

    Metrics
    * count
    * bases

    Contact ebelter\@genome.wustl.edu for help
HELP
}

my %supported_types = (
    sanger => { format => 'fastq', reader_subclass => 'FastqReader', writer_subclass => 'FastqWriter', },
    #illumina => { format => 'fastq', reader_subclass => 'FastqReader', writer_subclass => 'FastqWriter', },
    phred => { format => 'fasta', reader_subclass => 'PhredReader', writer_subclass => 'PhredWriter', },
);

sub valid_types {
    return (qw/ sanger illumina phred/);
}

sub _resolve_type_for_file {
    my ($self, $file) = @_;

    Carp::Confess('No file to resolve type') if not $file;

    my ($ext) = $file =~ /\.(\w+)$/;
    if ( not $ext ) {
        $self->error_message('Failed to get extension for file: '.$file);
        return;
    }

    my %file_exts_and_formats = (
        fastq => 'sanger',
        fasta => 'phred',
        fna => 'phred',
        fa => 'phred',
    );
    return $file_exts_and_formats{$ext} if $file_exts_and_formats{$ext};
    $self->error_message('Failed to resolve type for file: '.$file);
    return;
}

sub _reader_class {
    my $self = shift;
    if ( not $self->input ) {
        return 'Genome::Utility::IO::StdinRefReader';
    }
    if ( not $supported_types{ $self->type_in }->{reader_subclass} ) {
        $self->error_message('Invalid type in: '.$self->type_in);
        return;
    }
    return 'Genome::Model::Tools::FastQual::'.$supported_types{ $self->type_in }->{reader_subclass};
}

sub _writer_class {
    my $self = shift;
    if ( not $self->output ) {
        return 'Genome::Utility::IO::StdoutRefWriter';
    }
    if ( not $supported_types{ $self->type_out }->{writer_subclass} ) {
        $self->error_message('Invalid type out: '.$self->type_out);
        return;
    }
    return 'Genome::Model::Tools::FastQual::'.$supported_types{ $self->type_out }->{writer_subclass};
}

sub _enforce_type {
    my ($self, $type) = @_;

    Carp::confess('No type given to validate') if not $type;

    my @valid_types = $self->valid_types;
    if ( not grep { $type eq $_ } @valid_types ) {
        $self->error_message("Invalid type ($type). Must be ".join(', ', @valid_types));
        return;
    }

    return $type;
}

sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    return if not $self;

    my @input = $self->input;
    my $type_in = $self->type_in;
    if ( @input ) {
        if ( @input > 2 ) {
            $self->error_message('Can only handle 1 or 2 inputs');
            return;
        }
        if ( $input[0] eq '-' ) { # STDIN
            if ( @input > 1 ) { # Cannot have morethan one STDIN
                $self->error_message('Multiple STDIN inputs given: '.$self->_input_to_string);
                return;
            }
            if ( not $type_in ) {
                $self->error_message('Input from STDIN, but no type in given');
                return;
            }
        }
        else { # FILES
            if ( defined $self->paired_input and @input > 2 ) {
                $self->error_message('Cannot use paired_input with more than 2 inputs');
                return;
            }
            if ( not $type_in ) {
                $type_in = $self->_resolve_type_for_file($input[0]);
                return if not $type_in;
                $self->type_in($type_in);
            }
        }
    }
    else {
        if ( $type_in ) { # PIPE is always sanger
            $self->error_message('Do not set type in when piping between fast-qual commands');
            return;
        }
        if ( defined $self->paired_input ) {
            $self->error_message('Do not set paired_input when piping between fast-qual commands');
            return;
        }
    }

    my @output = $self->output;
    my $type_out = $self->type_out;
    if ( @output ) {
        if ( $output[0] eq '-' ) { # STDOUT
            if ( @output > 1 ) { # Cannot have morethan one STDOUT
                $self->error_message('Multiple STDOUT outputs given: '.$self->_output_to_string);
                return;
            }
            if ( not $type_out ) {
                $self->type_out('sanger');
            }
        }
        else { # FILES
            if ( not $type_out ) {
                $type_out = $self->_resolve_type_for_file($output[0]);
                return if not $type_out;
                $self->type_out($type_out);
            }
        }
    }
    else {
        if ( $type_out ) { # PIPE is always sanger
            $self->error_message('Do not set type out when piping between fast-qual commands.');
            return;
        }
        if ( $self->paired_output ) {
            $self->error_message('Do not set paired_output when piping between fast-qual commands.');
            return;
        }
    }

    $self->_add_result_observer;  #confesses on error

    return $self;
}

sub execute {
    my $self = shift;

    if ( $self->input == $self->output and $self->type_in eq $self->type_out ) {
        $self->error_message("Cannot read and write the same number of input/outputs and with the same type in/out");
        return;
    }

    my ($reader, $writer) = $self->_open_reader_and_writer
        or return;
    if ( $reader->isa('Genome::Utility::IO::StdinRefReader') ) {
        $self->error_message('Cannot read from a PIPE!');
        return;
    }
    if ( $writer->isa('Genome::Utility::IO::StdoutRefWriter') ) {
        $self->error_message('Cannot write to a PIPE!');
        return;
    }

    while ( my $seqs = $reader->read ) {
        $writer->write($seqs);
    }

    return 1;
}

sub _open_reader_and_writer {
    my $self = shift;

    my $reader_class = $self->_reader_class;
    return if not $reader_class;

    my %reader_params;
    my @input = $self->input;
    if ( @input ) { # STDIN/FILES
        $reader_params{files} = \@input;
        $reader_params{is_paired} = $self->paired_input;
    }

    my $reader = eval{ $reader_class->create(%reader_params); };
    if ( not  $reader ) {
        $self->error_message("Failed to create reader for input: ".$self->_input_to_string);
        return;
    }
    $self->_reader($reader);

    my $writer_class = $self->_writer_class;
    return if not $writer_class;

    my %writer_params;
    my @output = $self->output;
    if ( @output ) { # STDOUT/FILES
        $writer_params{files} = \@output;
        $writer_params{is_paired} = $self->paired_output;
    }

    my $writer = eval{ $writer_class->create(%writer_params); };
    if ( not $writer ) {
        $self->error_message('Failed to create writer for output ('.$self->_output_to_string.'): '.($@ || 'no error'));
        return;
    }

    if ( $self->metrics_file_out ) {
        $writer->metrics( Genome::Model::Tools::FastQual::Metrics->create() );
    }

    $self->_writer($writer);

    return ( $self->_reader, $self->_writer );
}

#< Observers >#
sub _add_result_observer { # to write metrics file
    my $self = shift;

    my $result_observer = $self->add_observer(
        aspect => 'result',
        callback => sub {
            #print Dumper(\@_);
            my ($self, $method_name, $prior_value, $new_value) = @_;
            # skip if new result is not successful
            if ( not $new_value ) {
                return 1;
            }

            if ( not $self->_writer ) {
                Carp::confess('No writer found!');
            }
            $self->_writer->flush;

            # Skip if we don't have a metrics file
            my $metrics_file = $self->metrics_file_out;
            return 1 if not $self->metrics_file_out;

            # Problem if the writer or writer metric object does not exist
            if ( not $self->_writer->metrics ) { # very bad
                Carp::confess('Requested to output metrics, but none were found for writer:'.$self->_writer->class);
            }

            unlink $metrics_file if -e $metrics_file;
            my $fh = eval{ Genome::Sys->open_file_for_writing($metrics_file); };
            if ( not $fh ) {
                Carp::confess("Cannot open metrics file ($metrics_file) for writing: $@");
            }

            my $metrics_as_string = $self->_writer->metrics->to_string;
            $fh->print($metrics_as_string);
            $fh->close;
            return 1;
        }
    );

    if ( not defined $result_observer ) {
        Carp::confess("Cannot create result observer");
    }

    return 1;
}

1;

