package Genome::Model::Build::Command::Remove;

use strict;
use warnings;

use Genome;

class Genome::Model::Build::Command::Remove {
    is => 'Genome::Model::Build::Command::Base',
    has_optional => [
        keep_build_directory => {
            is => 'Boolean',
            default_value => 0,
            doc => 'A boolean flag to allow the retention of the model directory after the model is purged from the database.(default_value=0)',
        },
    ],
};

sub sub_command_sort_position { 7 }

sub help_brief {
    "Remove a build.";
}

sub help_detail {
    "This command will remove a build from the system.  The rest of the model remains the same, as does independent data like alignments.";
}

sub execute {
    my $self = shift;

    my @builds = $self->builds;
    my $build_count = scalar(@builds);
    my @errors;
    for my $build (@builds) {
        my $transaction = UR::Context::Transaction->begin();
        my $display_name = $build->__display_name__;
        my $remove_build = Genome::Command::Remove->create(items => [$build], _deletion_params => [keep_build_directory => $self->keep_build_directory]);
        my $successful = eval {
            my @__errors__ = $build->__errors__;
            unless (@__errors__) {
                push @__errors__, map { $_->__errors__ } $build->instrument_data_assignments;
            }
            if (@__errors__) {
                die "build or instrument data has __errors__, cannot remove: " . join('; ', @__errors__);
            }
            $remove_build->execute;
        };
        if ($successful) {
            $self->status_message("Successfully removed build (" . $display_name . ").");
            $transaction->commit();
        }
        else {
            push @errors, "Failed to remove build (" . $display_name . "): $@.";
            $transaction->rollback();
        }
    }

    $self->display_summary_report(scalar(@builds), @errors);

    return !scalar(@errors);
}

1;
