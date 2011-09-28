package Genome::Model::Tools::Dbsnp::Import;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Dbsnp::Import {
    is => 'Genome::Model::Tools::Dbsnp',
    has => [
        input_directory => {
            is => 'Path',
            is_input => 1,
            doc => 'Directory containing dbsnp flat files',
        },
        filename_pattern => {
            is => 'Text',
            is_input => 1,
            default => 'ds_flat_chX.flat',
            doc => 'String representing the naming scheme of the flatfiles in the input-directory.  The first instance of the character "X" will be replaced with the chromosome designator to create the file name (ex: ds_flat_chX.flat)',
        },
        output_file => {
            is => 'Path',
            is_output => 1,
            doc => 'Path to the final output file in .bed',
        }
    ],
};

sub help_brief {
    'Create unfiltered bed file from Dbsnp flat files'
}

sub help_synopsis {
    return <<EOS
gmt dbsnp import --input_directory ./dbsnp_flat_file_dir --output_file output.bed
EOS
}

sub help_detail {
    return <<EOS
This command takes a directory of Dbsnp flat files, parses them out, and creates a single, sorted bed file suitable
for creating a Genome::Model::Build::ImportedVariationList
EOS
}

sub chromosome_designators {
    return qw(1 10 11 12 13 14 15 16 17 18 19 2 20 21 22 3 4 5 6 7 8 9 MT X Y);
}

sub execute {
    my $self = shift;
    my $input_dir = $self->input_directory;
    unless (-d $input_dir){
        $self->error_message("Input directory $input_dir is not a directory, exiting");
        return 0;
    }
    my $temp_dir = Genome::Sys->base_temp_directory();

    my @output_files;

    for my $chromosome ($self->chromosome_designators){
        my $flatfile = $self->filename_pattern;
        $flatfile =~ s/X/$chromosome/;
        my $flatfile_path = join('/', $input_dir, $flatfile);
        my $output_file = join("/", $temp_dir, "$flatfile.bed");
        unless(Genome::Model::Tools::Dbsnp::Import::Flatfile->execute(flatfile => $flatfile_path, output_file => $output_file)){
            $self->error_message("Failed to import flatfile $flatfile: $@");
            return 0;
        }
        push @output_files, $output_file;
    }

    unless(Genome::Model::Tools::Joinx::Sort->execute(input_files => \@output_files, output_file => $self->output_file)){
        $self->error_message("Failed to merge and sort imported flatflies: $@");
        return 0;
    }
    #TODO: do gabe's white/black listing, make a feature list out of the filtered bed file and use it to create a new build of the dbsnp model

    return 1;
}

1;
