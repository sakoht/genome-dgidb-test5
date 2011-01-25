package Genome::Model::Tools::Bed::Convert;

use strict;
use warnings;

use Genome;
use Carp qw/croak/;
use File::Basename;
use Sort::Naturally;

class Genome::Model::Tools::Bed::Convert {
    is => ['Command'],
    has_input => [
        source => {
            is => 'File',
            shell_args_position => 1,
            doc => 'The original file to convert to BED format',
        },
        output => {
            is => 'File',
            shell_args_position => 2,
            doc => 'Where to write the output BED file',
        },
    ],
    has => {
        sorted_filename => {
            is => 'File',
            calculate_from => 'output',
            calculate => q|
                $output =~ s/\.bed$//;
                return "$output.v1.bed";
            |
        },
    },
    has_transient_optional => [
        _input_fh => {
            is => 'IO::File',
            doc => 'Filehandle for the source variant file',
        },
        _output_fh => {
            is => 'IO::File',
            doc => 'Filehandle for the output BED file',
        },
        _last_chrom => {
            is => 'Text',
            doc => 'Instance variable, last chromosome seen',
        },
        _need_chrom_sort => {
            is => 'Boolean',
            default_value => 0,
            doc => 'Instance variable, true if chromosomes were written out of order',
        },
    ]
};

sub help_brief {
    "Tools to convert other variant formats to BED.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
  gmt bed convert ...
EOS
}

sub help_detail {                           
    return <<EOS
    This is a collection of small tools to take variant calls in various formats and convert them to a common BED format (using the first four or five columns).
EOS
}

sub execute {
    my $self = shift;
    
    unless($self->initialize_filehandles) {
        return;
    }
    
    my $retval = $self->process_source;
    
    $self->close_filehandles;

    return unless $retval;

    if ($self->_need_chrom_sort) {
        my $sort_cmd = Genome::Model::Tools::Bed::ChromSort->create(
            input => $self->output,
            output => $self->sorted_filename
        );

        if ($sort_cmd->execute()) {
            unlink($self->output);
        } else {
            $self->error_message("Failed to sort bed file " . $self->output);
            return;
        }
    } else {
        rename($self->output, $self->sorted_filename);
    }
    symlink(basename($self->sorted_filename), $self->output);

    return 1;
}

sub initialize_filehandles {
    my $self = shift;
    
    if($self->_input_fh || $self->_output_fh) {
        return 1; #Already initialized
    }
    
    my $input = $self->source;
    my $output = $self->output;
    
    eval {
        my $input_fh = Genome::Sys->open_file_for_reading($input);
        my $output_fh = Genome::Sys->open_file_for_writing($output);
        
        $self->_input_fh($input_fh);
        $self->_output_fh($output_fh);
    };
    
    if($@) {
        $self->error_message('Failed to open file. ' . $@);
        $self->close_filehandles;
        return;
    }
    
    return 1;
}

sub close_filehandles {
    my $self = shift;
    
    my $input_fh = $self->_input_fh;
    close($input_fh) if $input_fh;
    
    my $output_fh = $self->_output_fh;
    close($output_fh) if $output_fh;
    
    return 1;
}

sub format_line {
    my ($self, @values) = @_;
    if (@values < 5) {
        croak "Not enough fields to write bed file in input: ".join("\t", @values);
    }
    splice(@values,3,2, join('/', @values[3,4]));
    # if no quality field is present, push -
    push(@values, '-') if @values < 5;
    return join("\t", @values);
}

sub write_bed_line {
    my $self = shift;

    # If the current chromosome ($_[0]) is less than the previous one, we'll need to sort
    if ($self->_last_chrom and ncmp($self->_last_chrom, $_[0]) > 0) {
        $self->_need_chrom_sort(1);
    }
    $self->_last_chrom($_[0]);

    my $output_fh = $self->_output_fh;
    print $output_fh $self->format_line(@_)."\n";
    
    return 1;
}

sub process_source {
    my $self = shift;

    $self->error_message('The process_source() method should be implemented by subclasses of this module.');
    return;
}

1;
