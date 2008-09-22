package Genome::Model::Tools::PhredPhrap::Phds;

use strict;
use warnings;

use above 'Genome';

class Genome::Model::Tools::PhredPhrap::Phds {
    is => 'Genome::Model::Tools::PhredPhrap::Base',
    has => [
    phd_source => {
        is => 'String', #file_r
        doc => "Source of PHDs",
    },
    ],
};

require Genome::Model::Tools::Fasta::PhdToFnq;
use Data::Dumper;

sub help_brief {
    return 'Phrap starting with PHDs in a project\'s phd_dir';
}

sub help_detail {
    return '';
}

sub _files_to_remove {
    return (qw/ default_fasta_file default_qual_file /);
}

sub _handle_input {
    my $self = shift;

    $self->info_msg("Verifying PHDs");
    my $phd_file = $self->_verify_phds;

    $self->info_msg("PHD to FASTA and Quality");
    $self->_phd2fnq($phd_file);

    return 1;
}

sub _verify_phds {
    my $self = shift;

    my $phd_dir = $self->_project->phd_dir;
    my $dh = IO::Dir->new($phd_dir)
        or $self->fatal_msg( sprintf('Can\'t open dir (%s)', $phd_dir) );
    my $phd_file = $self->default_phd_file;
    unlink $phd_file if -e $phd_file;
    my $phd_fh = IO::File->new("> $phd_file")
        or $self->fatal_msg("Can\'t open phd file ($phd_file) for writing");

    while ( my $phd_name = $dh->read ) {
        next unless $phd_name =~ m#\.phd\.\d+$#;
        # TODO Exclude
        $phd_fh->print("$phd_name\n");
    }

    $dh->close;
    $phd_fh->close;

    $self->fatal_msg("No phds found in directory ($phd_dir)") unless -s $phd_file;

    return $phd_file;
}

sub _phd2fnq {
    my ($self, $phd_file) = @_;

    my $phd2fnq = Genome::Model::Tools::PhdToFasta->new(
        phd_file => $phd_file,
        phd_dir => $self->_project->phd_dir,
        fasta_file => $self->fasta_file,
    );

    return $phd2fnq->execute;
}

1;

#$HeadURL$
#$Id$
