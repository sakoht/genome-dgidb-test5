package Genome::Model::GenePrediction::Bacterial;

use strict;
use warnings;

use Genome;

class Genome::Model::GenePrediction::Bacterial {
    is => 'Genome::Model::GenePrediction',
    has => [
        # Processing profile parameters
        minimum_sequence_length => { 
            via => 'processing_profile', 
        },
        runner_count => { 
            via => 'processing_profile',
        },
        skip_acedb_parse => { 
            via => 'processing_profile',
        },
        skip_core_gene_check => {
            via => 'processing_profile',
        },
    ],
    has_optional => [
        dev => {
            is => 'Boolean',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'dev' ],
            doc => 'If set, dev databases are used instead of production databases',
        },
        run_type => {
            is => 'String', # TODO Does this affect processing? Why do we need to note it?
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'run_type' ],
            doc => 'A three letter identifier appended to locus id, (DFT, FNL, etc)',
        },
        assembly_version => {
            is => 'String', # TODO Can this be removed or derived from the assembly in some way?
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'assembly_version' ],
            doc => 'This notes the assembly version, but doesn\'t really seem to change...',
        },
        project_type => {
            is => 'String', # TODO What is this? Why do we need it?
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'project_type' ],
            doc => 'The type of project this data is being generated for (HGMI, for example)',
        },
        pipeline_version => {
            is => 'String', # TODO Can this be removed? Why do we need it?
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'pipeline_version' ],
            doc => 'Apparently, this notes the pipeline version.', 
        },
        acedb_version => {
            is => 'String', # TODO If we can figure out a way to automate switching to a new db, this can go away
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'acedb_version' ],
            doc => 'Notes the version of aceDB that results should be uploaded to',
        },
        nr_database_location => {
            is => 'Path', # TODO Once using local NR is fully tested and trusted, this param can be removed
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'nr_database_location' ],
            doc => 'The NR database that should be used by default, may be overridden by local copies',
        },
        use_local_nr => {
            is => 'Boolean',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'use_local_nr' ],
            doc => 'If set, local NR databases are used by blast jobs instead of accessing the default location',
        },
    ],
};

sub create {
    my $class = shift;
    my %params = @_;
    
    # Anything left in the params hash will be made into an input on the model
    my $self = $class->SUPER::create(
        name                             => delete $params{name},
        processing_profile_id            => delete $params{processing_profile_id},
        subject_name                     => delete $params{subject_name},
        subject_type                     => delete $params{subject_type},
        subject_id                       => delete $params{subject_id},
        subject_class_name               => delete $params{subject_class_name},
        auto_assign_inst_data            => delete $params{auto_assign_inst_data},
        auto_build_alignments            => delete $params{auto_build_alignments},
        create_assembly_model            => delete $params{create_assembly_model},
        assembly_processing_profile_name => delete $params{assembly_processing_profile_name},
        start_assembly_build             => delete $params{start_assembly_build},
    );
    return unless $self;

    # Add inputs to the model
    for my $key (keys %params) {
        $self->add_input(
            value_class_name => 'UR::Value',
            value_id => $params{$key},
            name => $key,
        );
    }

    return $self;
}

1;

