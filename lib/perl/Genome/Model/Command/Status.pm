package Genome::Model::Command::Status;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Status {
    is => 'Genome::Command::Base',
    doc => "prints status of non-succeeded latest-builds and tallies latest-build statuses",
    has => [
        models => {
            is => 'Genome::Model',
            is_many => 1,
            require_user_verify => 0,
            doc => 'Model(s) to check latest-build status. Resolved from command line via text string.',
            shell_args_position => 1,
        },
    ],
};

sub execute {
    my $self = shift;

    my %status;
    for my $model ($self->models) {
        my $build = $model->latest_build;
        my $model_name = $model->name;
        my $build_id = ($build ? $build->id : 'N/A      ');
        my $build_status = ($build ? $build->status : 'Buildless');
        $status{$build_status}++;
        if ($build_status ne 'Succeeded') {
            $self->status_message("$model_name\t".$build_id."\t$build_status");
        }
    }

    my $total;
    for my $key (sort keys %status) {
        $total += $status{$key};
    }

    for my $key (sort keys %status) {
        print "$key: $status{$key}\t";
    }
    print "Total: $total\n";

    return 1;
}

1;
