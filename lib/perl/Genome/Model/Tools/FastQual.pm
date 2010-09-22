package Genome::Model::Tools::FastQual;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
use File::Basename;
#require Genome::Model::Tools::FastQual::FastaQualReader;
#require Genome::Model::Tools::FastQual::FastaQualWriter;
require Genome::Model::Tools::FastQual::FastqSetReader;
require Genome::Model::Tools::FastQual::FastqSetWriter;
require Genome::Utility::IO::StdinRefReader;
require Genome::Utility::IO::StdoutRefWriter;

class Genome::Model::Tools::FastQual {
    is  => 'Command',
    is_abstract => 1,
    has => [
        input => {
            is => 'Text',
            is_many => 1,
            is_input => 1,
            doc => 'Input files, or "PIPE" if reading from another program. If multiple files are given for fastq types (sanger, illumina), one sequence will be read from each file and then handled as a set.',
            # TODO includes fasta:
            # doc => 'Input files, or "PIPE" if reading from another program. If multiple files are given for fastq types (sanger, illumina), one sequence will be read from each file and then handled as a set. If multiple files are given for type phred (fasta), the first file should be the sequences, and the second file should be the qualities.',
        }, 
        type_in => {
            is  => 'Text',
            default_value => 'sanger',
            is_optional => 1,
            is_input => 1,
            doc => 'The sequence and quality type of the input. Valid values are: '.join(' ', __PACKAGE__->valid_types).'.',
            # TODO includes phred (fasta):
            # doc => 'The sequence and quality type. If not given, an attempt will be made to guess the type. If the file ends in "fasta", "fna", or "fa", the type will assumed to be phred (fasta). If the file ends with "fastq", it will assumed to be sanger (fastq).',
        },
        output => {
            is => 'Text',
            is_many => 1,
            is_input => 1,
            doc => 'Output files, or "PIPE" if writing to another program. If multiple files are given for fastq types (sanger, illumina), one sequence from each set will be written to each file.',
            # TODO includes fasta: 
            # doc => 'Output files, or "PIPE" if writing from another program. If multiple files are given for fastq types (sanger, illumina), one sequence from each set will be written to each file. If multiple files are given for type phred (fasta), the sequences will be written to the first file, and the qualities will eb written to the second file.',
        },
        _writer => {
            is_optional => 1,
        },
        type_out => {
            is  => 'Text',
            default_value => 'sanger',
            is_optional => 1,
            is_input => 1,
            doc => 'The sequence and quality type of the output. Currently, this is ognored and the type of the input is used. Valid values are: '.join(' ', __PACKAGE__->valid_types).'.',
            # TODO includes phred (fasta):
            # doc => 'The sequence and quality type. If not given, an attempt will be made to guess the type. If the file ends in "fasta", "fna", or "fa", the type will assumed to be phred (fasta). If the file ends with "fastq", it will assumed to be sanger (fastq).',
        },
        metrics_file => {
            is => 'Text',
            is_optional => 1,
            doc => 'Output general sequence metrics to this file. Current metrics include: count, bases',
        },
        _metrics => {
            is => 'HASH',
            is_optional => 1,
        },
    ],
};

#< Helps >#
sub help_brief {
    return <<HELP
    Process fastq and fasta/quality sequences
HELP
}

sub help_detail { # empty ok
    return <<HELP 
HELP
}
#<>#

#< Types and Formats >#
my %supported_types = (
    sanger => { format => 'fastq', },
    illumina => { format => 'fastq', },
    phred => { format => 'fasta', file_exts => [qw/ fna fa /], },
);
sub valid_types {
    return keys %supported_types;
}

sub validate_type {
    my ($self, $type) = @_;

    unless ( defined $type ) {
        Carp::confess("Cannot validate type. It is not defined");
    }

    my @valid_types = $self->valid_types;
    unless ( grep { $type eq $_ } @valid_types ) {
        Carp::confess("Cannot validate type ($type). It must be: ".join(', ', @valid_types));
    }

    return $type;
}

sub format_for_type {
    my ($self, $type) = @_;

    unless ( defined $type ) {
        Carp::confess("Cannot get format for type. It is not defined");
    }

    unless ( exists $supported_types{$type} ) {
        Carp::confess("Cannot get format for type ($type). It must be: ".join(', ', $self->valid_types));
    }

    return $supported_types{$type}->{format};
}

sub _enforce_type {
    my $self = shift;

    my $type = $self->type_in;
    unless ( defined $type ) {
        Carp::confess("No type set.");
    }
    my @valid_types = $self->valid_types;
    unless ( grep { $type eq $_ } @valid_types ) {
        Carp::confess("Invalid type ($type). Must be ".join(', ', @valid_types));
    }

    return $type;
}
#<>#

#< Create >#
sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_)
        or return;

    $self->_add_result_observer;  #confesses on error

    if ( not defined $self->type_out ) {
        $self->type_out( $self->type_in );
    }

    return $self;
}
#<>#

#< Reader Writer >#
sub _open_reader {
    my $self = shift;

    my @input = $self->input;
    unless ( @input ) {
        Carp::confess("Input files or 'PIPE' is required.");
    }

    if ( $input[0] eq 'PIPE' ) {
        return $self->_open_stdin_reader;
    }

    my $type = $self->_enforce_type
        or return;

    my $reader;
    eval{
        $reader = Genome::Model::Tools::FastQual::FastqSetReader->create(
            files => \@input,
        );
    };
    unless ( $reader ) {
        $self->error_message("Can't create fastq reader for input files (".join(', ', @input)."): $@");
        return;
    }

    return $reader;
}

sub _open_stdin_reader {
    my $self = shift;

    # open the stdin reader
    my $reader = Genome::Utility::IO::StdinRefReader->create()
        or Carp::confess("Can't open pipe to STDIN");

    # get the reader meta, set alarm b/c it will hang if nothing is there
    my $reader_info;
    eval {
        local $SIG{ALRM} = sub{ die; };
        alarm 5;
        $reader_info = $reader->read;
        alarm 0;
    };
    unless ( $reader_info ) {
        Carp::confess("No pipe meta info. Are you sure you wanted to read from a pipe?");
    }

    if ( not defined $reader_info->{type_in} ) {
        Carp::confess("No type in from pipe");
    }
    $self->type_in( $reader_info->{type_in} );

    if ( not defined $reader_info->{type_in} ) {
        Carp::confess("No type out from pipe");
    }
    $self->type_out( $reader_info->{type_out} );

    $self->_enforce_type;
    
    return $reader;
}

sub _open_writer {
    my $self = shift;

    my @output = $self->output;
    unless ( @output ) {
        Carp::confess("Output files or 'PIPE' is required.");
    }

    my $type = $self->_enforce_type
        or return;
    my $format = $self->format_for_type($type);

    my $writer;
    if ( $output[0] eq 'PIPE' ) {
        $writer = $self->_open_stdout_writer; # confess in sub
    }
    elsif ( $format eq  'fastq' ) {
        $writer = $self->_open_fastq_set_writer(@output); # confess in sub
    }
    else { 
        Carp::confess("Cannot open writer, unknown output type ($type).");
    }

    if ( $self->metrics_file ) {
        $self->_setup_write_observer($writer); # confess in sub
    }

    return $self->_writer($writer);
}

sub _open_stdout_writer {
    my $self = shift;

    # open stdout ref writer
    my $writer = Genome::Utility::IO::StdoutRefWriter->create
        or Carp::confess("Can't open pipe to STDOUT");
    # write the meta info - TODO output type
    $writer->write({
            type_in => $self->type_in,
            type_out => $self->type_out,
        });

    return $writer;
}

sub _open_fastq_set_writer {
    my ($self, @output) = @_;

    my $writer;
    eval{
        $writer = Genome::Model::Tools::FastQual::FastqSetWriter->create(
            files => \@output,
        );
    };
    unless ( $writer ) {
        Carp::confess("Can't create fastq set writer for output files (".join(', ', @output)."): $@");
    }

    return $writer;
}

#< Observers >#

# Need these as class vars
my %metrics; # writer class and id => metrics
my @writer_classes_overloaded; # writer classes that are overloaded below
#

sub _add_result_observer { # to write metrics file
    my $self = shift;

    my $result_observer = $self->add_observer(
        aspect => 'result',
        callback => sub {
            #print Dumper(\@_);
            my ($self, $method_name, $prior_value, $new_value) = @_;
            if ( not $new_value ) {
                return 1;
            }

            # Skip if we don't have a metrics file or a writer
            my $metrics_file = $self->metrics_file;
            return 1 if not defined $self->_writer or not defined $self->metrics_file;

            my $writer_class_id = ref( $self->_writer ).' '.$self->_writer->id;
            my $metrics = $metrics{$writer_class_id};
            if ( not defined $metrics ) { # very bad
                Carp::confess("Requested to output metrics, but none were found for writer ($writer_class_id)");
            }

            unlink $metrics_file if -e $metrics_file;
            my $fh;
            eval{
                $fh= Genome::Utility::FileSystem->open_file_for_writing($metrics_file);
            };
            unless ( $fh ) {
                Carp::confess("Cannot open metrics file ($metrics_file) for writing: $@");
            }

            for my $stat ( sort keys %$metrics) {
                $fh->print( $stat.'='.$metrics->{$stat}."\n");
            }
            $fh->close;
            return 1;
        }
    );

    if ( not defined $result_observer ) {
        Carp::confess("Cannot create result observer");
    }

    return 1;
}

sub _setup_write_observer { # to add to metrics when seqs are written
    my ($self, $writer) = @_;

    # Writer Class and ID - set in writers observed, 
    my $writer_class_id = ref($writer).' '.$writer->id;
    return 1 if exists $metrics{$writer_class_id}; # already observing
    $metrics{$writer_class_id} = { 
        bases => 0, 
        count => 0,
    }; # Add more??

    # Don't overload the writer class more than once
    my $writer_class = ref($writer);
    unless (  grep { $writer_class eq $_ } @writer_classes_overloaded ) {
        my $write_method = $writer_class.'::write';
        my $write = \&{$write_method};
        no strict 'refs';
        no warnings 'redefine';
        *{$write_method} = sub{ 
            $write->(@_) or return; 
            my $writer_class_id = ref($_[0]).' '.$_[0]->id;
            my $metrics = $metrics{$writer_class_id};
            for ( @{$_[1]} ) { 
                $metrics->{bases} += length($_->{seq});
                $metrics->{count}++;
            }
            return 1;
        }; 
        use strict;
        use warnings;
        push @writer_classes_overloaded, $writer_class;
    }

    return 1;
}
#<>#

1;

