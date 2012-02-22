package Genome::Model::MutationalSignificance::Command::MergeMafFiles;

use strict;
use warnings;

use Genome;
use Data::Dumper;


class Genome::Model::MutationalSignificance::Command::MergeMafFiles {
    is => ['Command::V2'],
    has_input => [
        maf_files => {
            is => 'Text',
            is_many => 1,
        },
        build => {
            is => 'Genome::Model::Build',
        },
    ],
    has_output => [
        maf_path => {
            is => 'String'},
    ],
};

sub execute {
    my $self = shift;

    my $count = 0;
    my $maf_path = $self->build->data_directory."/final.maf";
    my $out = Genome::Sys->open_file_for_writing($maf_path);
    #Print header line once
    my $header_printed = 0;
    foreach my $file ($self->maf_files) {
        my @lines = Genome::Sys->read_file($file);
        #Don't include the header line for each file
        if (!$header_printed) {
            $out->print($lines[0]);
            $header_printed = 1;
        }
        for (my $i = 1; $i < scalar @lines; $i++) {
            $out->print($lines[$i]);
        }
        $count++;
    }
    $out->close;

    $self->maf_path($maf_path);

    my $status = "Merged $count MAF files in $maf_path";
    $self->status_message($status);
    return 1;
}

1;
