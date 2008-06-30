package Genome::Model::Tools::Newbler::NewMapping;

use strict;
use warnings;

class Genome::Model::Tools::Newbler::NewMapping {
    is => 'Genome::Model::Tools::Newbler',
    has => [
            dir => {
                    is => 'String',
                    doc => 'pathname of the output directory',
                },
        ],

};

sub help_brief {
"genome-model tools newbler new-mapping --dir=DIR";
}

sub help_detail {
    return <<"EOS"

EOS
}

sub execute {
    my $self = shift;

    $DB::single=1;
    my $cmd = $self->full_bin_path('createProject') .' -t map '. $self->dir;
    my $rv = system($cmd);
    unless ($rv == 0) {
        $self->error_message("non-zero return status from command '$cmd'");
        return
    }
    return 1;
}

1;

