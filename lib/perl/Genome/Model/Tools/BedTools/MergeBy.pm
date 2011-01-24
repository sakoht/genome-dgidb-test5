package Genome::Model::Tools::BedTools::MergeBy;

use strict;
use warnings;

use Genome;

my $DEFAULT_MAX_DISTANCE = 0;
my $DEFAULT_EXCLUDE_TYPES = 'intron,utr_exon,rna';
my $DEFAULT_FORCE_STRANDEDNESS = 0;
my $DEFAULT_MERGE_BY = 'gene';

class Genome::Model::Tools::BedTools::MergeBy {
    is => 'Genome::Model::Tools::BedTools',
    has_input => [
        input_file => {
            is => 'Text',
            doc => 'The input BED file to be merged with names following this convention, GENE:TRANSCRIPT:TYPE:ORDINAL',
        },
        output_file => {
            is => 'Text',
            doc => 'The output file to write coverage output',
        },
        maximum_distance => {
            is => 'Number',
            is_optional => 1,
            doc => 'Maximum distance between features allowed for features to be merged. For value 0(zero), overlapping & book-ended features are merged.',
            default_value => $DEFAULT_MAX_DISTANCE,
        },
        merge_by => {
            is => 'Text',
            doc => 'The granularity to merge objects in a BED file.',
            default_value => $DEFAULT_MERGE_BY,
            valid_values => ['exome','gene','transcript'],
        },
        exclude_types => {
            is => 'String',
            default_value => $DEFAULT_EXCLUDE_TYPES,
            doc => 'A comma delimited list of features to exclude any of: intron, utr_exon, cds_exon, and rna',
        },
        force_strandedness => {
            is => 'Boolean',
            is_optional => 1,
            default_value => $DEFAULT_FORCE_STRANDEDNESS,
            doc => 'Force strandedness.  That is, only merge features that are the same strand.',
        },
        delimiter => {
            is => 'Text',
            doc => 'The character that delimits GENE, TRANSCRIPT, TYPE, and ORDINAL',
            default_value => ':',
            valid_values => [':','_','.'],
        },
    ],
};


sub help_brief {
    "Merges overlapping or redundant annotation into one squashed representation of each gene",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
  gmt bed-tools merge-by-gene ...
EOS
}

sub help_detail {
    return <<EOS
This tool expects BED features to be named GENE:TRANSCRIPT:TYPE:ORDINAL.
The ORDINAL field is optional.  However, the GENE field is used to merge annotation.
In addition, by default all merged feature names are reported and strandedness is enforced.
More information about the BedTools suite of tools can be found at http://code.google.com/p/bedtools/. 
EOS
}

sub execute {
    my $self = shift;
    my $tmp_dir = Genome::Sys->create_temp_directory();

    my $input_fh = Genome::Sys->open_file_for_reading($self->input_file);
    my $output_fh = Genome::Sys->open_file_for_writing($self->output_file);
    my %exclude_types;
    if ($self->exclude_types) {
        my @exclude_types = split(',',$self->exclude_types);
        %exclude_types = map {$_ => 1} @exclude_types;
    }
    my %bed_lines;
    while (my $line = $input_fh->getline) {
        chomp($line);
        my ($chr,$start,$end,$name,$score,$strand) = split("\t",$line);
        my ($gene,$transcript,$type,$ordinal) = split($self->delimiter,$name);
        unless ($gene && $transcript && $type) {
            die('Failed to parse BED line name:  '. $name);
        }
        if ($exclude_types{$type}) { next; }
        my $key;
        if ($self->merge_by eq 'exome') {
            $key = 'exome';
        } elsif ($self->merge_by eq 'gene') {
            $key = $gene;
        } elsif ($self->merge_by eq 'transcript') {
            $key = $transcript;
        } elsif ($self->merge_by eq 'exon') {
            $key = $gene . $self->delimiter . $transcript . $self->delimiter . $type;
            if (defined $ordinal) {
                $key .= $self->delimiter . $ordinal;
            }
        }
        push @{$bed_lines{$key}}, $line;
    }
    my %merge_params = (
        report_names => 1,
        force_strandedness => $self->force_strandedness,
        maximum_distance => $self->maximum_distance,
        use_version => $self->use_version,
    );
    # The status messages slow this down
    # Genome::Model::Tools::BedTools::Merge::dump_status_messages(0);
    for my $key (keys %bed_lines) {
        my $key_dir = $tmp_dir .'/'. $key;
        Genome::Sys->create_directory($key_dir);
        my $unmerged_bed_file = $key_dir .'/unmerged.bed';
        my $unmerged_fh = Genome::Sys->open_file_for_writing($unmerged_bed_file);
        my @lines = @{$bed_lines{$key}};
        for my $line (@lines) {
            print $unmerged_fh $line ."\n";
        }
        $unmerged_fh->close;
        my $merged_bed_file = $key_dir .'/merged.bed';
        $merge_params{input_file} = $unmerged_bed_file;
        $merge_params{output_file} = $merged_bed_file;
        unless (Genome::Model::Tools::BedTools::Merge->execute(%merge_params)) {
            die('Failed to run mergeBed with params:  '. Data::Dumper::Dumper(%merge_params));
        }
        my $merged_bed_fh = Genome::Sys->open_file_for_reading($merged_bed_file);
        while (my $line = $merged_bed_fh->getline) {
            print $output_fh $line;
        }
        $merged_bed_fh->close;
        unless (File::Path::rmtree($key_dir)) {
            die('Failed to remove directory:  '. $key_dir);
        }
    }
    $output_fh->close;
}

1;
