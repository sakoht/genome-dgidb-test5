package Genome::ProcessingProfile::ReferenceAlignment::454;

use strict;
use warnings;

use Genome;

class Genome::ProcessingProfile::ReferenceAlignment::454 {
    is => 'Genome::ProcessingProfile::ReferenceAlignment',
};

sub stages {
    my @stages = qw/
                alignment
                variant_detection
                verify_successful_completion
    /;
    return @stages;
}

sub alignment_job_classes {
    my @sub_command_classes= qw/
        Genome::Model::Command::Build::ReferenceAlignment::AssignRun
        Genome::Model::Command::Build::ReferenceAlignment::AlignReads
    /;
    return @sub_command_classes;
}

sub variant_detection_job_classes {
    my @steps = qw/
                 Genome::Model::Command::Build::ReferenceAlignment::MergeAlignments
                 Genome::Model::Command::Build::ReferenceAlignment::FindVariations
             /;
    return @steps;
}

sub alignment_objects {
    my $self = shift;
    my $model = shift;
    return $model->unbuilt_instrument_data;
}

sub variant_detection_objects {
    my $self = shift;
    my $model = shift;
    return 1;
}

1;
