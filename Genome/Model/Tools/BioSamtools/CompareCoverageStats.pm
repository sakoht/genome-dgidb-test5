package Genome::Model::Tools::BioSamtools::CompareCoverageStats;

use strict;
use warnings;

use Genome;

my %sort_order = (
    label => 1,
    targets => 2,
    minimum_depth => 3,
    touched => 4,
    pc_touched => 5,
    target_base_pair => 6,
    covered_base_pair => 7,
    pc_target_space_covered => 8,
    mean_breadth => 9,
    stdev_breadth => 10,
    median_breadth => 11,
    targets_eighty_pc_breadth => 12,
    pc_targets_eighty_pc_breadth => 13,
    mean_depth => 14,
    stdev_depth => 15,
    depth_quartile_3 => 16,
    median_depth => 17,
    depth_quartile_1 => 18,
    gaps => 19,
    mean_gap_length => 20,
    stdev_gap_length => 21,
    median_gap_length => 22,
);

class Genome::Model::Tools::BioSamtools::CompareCoverageStats {
    is => ['Genome::Model::Tools::BioSamtools'],
    has_input => [
        input_files => {
            is => 'Text',
            doc => 'A list of input coverage stats summaries'
        },
        output_file => {
            is => 'Text',
            doc => 'A file path to store tab delimited output',
        },
        labels => {
            doc => 'A list of text strings to be used as labels for each input file.  Must retain same order as input files list.',
            is_optional => 1,
        }
    ],
};

sub create {
    my $class = shift;
    my %params = @_;
    # retain sort order of input files and labels if provided
    if ($params{labels}) {
        my $labels = delete($params{labels});
        my $input_files = delete($params{input_files});
        my $self = $class->SUPER::create(%params);
        $self->input_files($input_files);
        $self->labels($labels);
        return $self;
    } else {
        return $class->SUPER::create(%params);
    }
}

sub execute {
    my $self = shift;

    my @data;
    my $i = 0;
    my @labels;
    if ($self->labels) {
        @labels = @{$self->labels};
    }
    my @headers;
    for my $input_file (@{$self->input_files}) {
        my $label;
        if ($self->labels) {
            $label = $labels[$i++];
        }
        my $reader = Genome::Utility::IO::SeparatedValueReader->create(
            separator => "\t",
            input => $input_file,
        );

        unless ($reader) {
            $self->error_message("Can't create SeparatedValueReader for input file $input_file");
            return;
        }
        while (my $data = $reader->next) {
            if ($label) {
                $data->{label} = $label;
            }
            push @data, $data;
            unless (@headers) {
                @headers = sort hash_sort_order (keys %{$data});
            }
        }
        $reader->input->close;
    }
    my $writer = Genome::Utility::IO::SeparatedValueWriter->create(
        separator => "\t",
        headers => \@headers,
        output => $self->output_file,
    );
    for my $data (@data) {
        $writer->write_one($data);
    }
    $writer->output->close;
    return 1;
}

sub hash_sort_order {
    if (!defined($sort_order{$a}) || !defined($sort_order{$b})) {
        die('Failed to find sort order for column A '. $a .' or column B '. $b);
    }
    $sort_order{$a} <=> $sort_order{$b};
}

1;
