package Genome::Model::GenePrediction::Eukaryotic::MergeFiles;

use strict;
use warnings;

use Genome;
use Carp 'confess';

class Genome::Model::GenePrediction::Eukaryotic::MergeFiles {
    is => 'Command',
    has => [
        input_files => {
            is => 'FilePath',
            is_input => 1,
            is_many => 1,
            doc => 'Files to be merged together',
        },
        output_file => {
            is => 'FilePath',
            is_input => 1,
            is_output => 1,
            doc => 'Merged file output file',
        },
    ],
    has_optional => [
        remove_input_files => {
            is => 'Boolean',
            is_input => 1,
            default => 0,
            doc => 'If set, input files are removed after being merged',
        },
        merge_non_unique => {
            is => 'Boolean',
            is_input => 1,
            default => 0,
            doc => 'If unset, a file that appears more than once in the input list will only be merged once',
        },
    ],
};

sub help_brief { return 'Merges files together' };
sub help_synopsis { return help_brief() };
sub help_detail { return 'Merges files of any format together' };

sub execute {
    my $self = shift;

    my @input_files = grep { -e $_ and -s } $self->input_files;
    @input_files = $self->uniqify(@input_files) unless $self->merge_non_unique;

    if (@input_files) {
        $self->status_message("Merging together " . scalar @input_files . " files into " . $self->output_file);

        my $rv = Genome::Sys->cat(
            input_files => \@input_files,
            output_file => $self->output_file,
        );
        unless ($rv) {
            $self->error_message("Could not merge files!");
            return 0;
        }

        if ($self->remove_input_files) {
            $self->status_message("Removing input files!");
            my @unremoved = $self->remove_files(@input_files);
            if (@unremoved) {
                Carp::confess "Could not remove some input files: " . join(',', @unremoved);
            }
        }

        $self->status_message('Done merging!');
    }
    else {
        $self->status_message("No files to merge!");
    }

    return 1;
}

sub uniqify {
    my $self = shift;
    my @list = @_;
    return unless @list;
    my %unique;
    for my $item (@list) {
        $unique{$item} = 1;
    }
    return keys %unique;
}

sub remove_files { 
    my $self = shift;
    my @files = @_;

    my @unremoved;
    for my $file (@files) {
        my $rv = unlink $file;
        push @unremoved, $file unless $rv;
    }

    return @unremoved;
}

1;

