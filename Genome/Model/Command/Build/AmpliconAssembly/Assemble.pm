package Genome::Model::Command::Build::AmpliconAssembly::Assemble;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';

class Genome::Model::Command::Build::AmpliconAssembly::Assemble{
    is => 'Genome::Model::Event',
};

sub execute {
    my $self = shift;

    my $assemble = Genome::Model::Tools::AmpliconAssembly::Assemble->create(
        directory => $self->build->data_directory,
        sequencing_center => $self->model->sequencing_center,
        sequencing_platform => $self->model->sequencing_platform,
        assembler => 'phred_phrap',#$self->model->assembler,
        assembler_params => '-vector_bound 0 -trim_qual 0',
        #assembler_params => $self->model->assembler_params,
    )
        or return;
    $assemble->execute
        or return;

    return 1;
}

1;

#$HeadURL$
#$Id$
