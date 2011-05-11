package Genome::Model::Build::Command::ReferenceAlignment::MergedAlignmentBam;

use strict;
use warnings;

use Genome;

class Genome::Model::Build::Command::ReferenceAlignment::MergedAlignmentBam {
    is => 'Genome::Command::Base',
    doc => "List the path of the merged alignment BAMs for the provided builds.",
    has => [
        builds => {
            is => 'Genome::Model::Build::ReferenceAlignment',
            is_many => 1,
            shell_args_position => 1,
        },
    ],
};


sub help_detail {
    return "List the path of the merged alignment BAMs for the provided builds.";
}


sub execute {
    my $self = shift;

    my @builds = $self->builds;
    print join("\t", 'BUILD_ID', 'MODEL_NAME', 'MERGED_ALIGNMENT_BAM') . "\n";
    for my $build (@builds) {
        print join("\t", $build->id, $build->model_name, $build->whole_rmdup_bam_file) . "\n";
    }

    return 1;
}

1;

