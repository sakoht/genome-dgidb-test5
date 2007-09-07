package Genome::Model::Event;

use strict;
use warnings;

use Genome;
UR::Object::Class->define(
    class_name => 'Genome::Model::Event',
    is => ['Command'],
    english_name => 'genome model event',
    table_name => 'genome_model_event',
    id_by => [
        id => { is => 'integer' },
    ],
    has => [
        date_completed  => { is => 'timestamp', is_optional => 1 },
        date_scheduled  => { is => 'timestamp' },
        event_status    => { is => 'varchar2(32)' },
        event_type      => { is => 'varchar2(255)' },
        model           => { is => 'Genome::Model', id_by => 'model_id', constraint_name => 'event_genome_model' },
        lsf_job_id      => { is => 'varchar2(64)', is_optional => 1 },
        run             => { is => 'Genome::RunChunk', id_by => 'run_id', constraint_name => 'event_run' },
        user_name       => { is => 'varchar2(64)' },
    ],
    data_source => 'Genome::DataSource::Main',
);


sub create {
    my $class = shift;

    if (exists $ENV{'LSB_JOBID'}) {
        push(@_, 'lsf_job_id', $ENV{'LSB_JOBID'});
    }
    $class->SUPER::create(@_);
}
    

sub _shell_args_property_meta {
    # exclude this class' commands from shell arguments
    return grep { 
            $_->class_name ne __PACKAGE__ 
            or
            ($_->via and $_->via eq 'run')
        } shift->SUPER::_shell_args_property_meta(@_);
}


sub resolve_run_directory {
    my $self = shift;

    $DB::single = 1;
    return sprintf('%s/runs/%s/%s', Genome::Model->get($self->model_id)->data_directory,
                                    $self->run->sequencing_platform,
                                    $self->run->name);
}


1;
