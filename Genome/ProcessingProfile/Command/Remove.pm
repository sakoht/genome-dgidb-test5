package Genome::ProcessingProfile::Command::Remove;

use strict;
use warnings;

use Genome;

use Data::Dumper;

class Genome::ProcessingProfile::Command::Remove {
    is => 'Genome::ProcessingProfile::Command',
};

sub execute {
    my $self = shift;

    $self->_verify_processing_profile
        or return;

    # These are for convenience, and the ability to output the name and id upon successful removal
    my $pp = $self->processing_profile;
    my $pp_name = $pp->name;
    my $pp_id = $pp->id;

    unless ( $pp->delete ) {
        $self->error_message(
            sprintf(
                'Could not remove processing profile "%s" <ID: %s>', 
                $pp_name,
                $pp_id,
            )
        );
        return;
    }

    $self->status_message(
        sprintf(
            'Removed processing profile "%s" <ID: %s>', 
            $pp_name,
            $pp_id,
        )
    );

    return 1;
}

1;

#$HeadURL$
#$Id$
