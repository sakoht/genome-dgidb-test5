package Genome::ProcessingProfile::PooledAssemblyDecomposition;

use strict;
use warnings;
use Genome;

class Genome::ProcessingProfile::PooledAssemblyDecomposition {
    is => 'Genome::ProcessingProfile',
    has => [
        server_dispatch => {
            is_constant => 1,
            is_class_wide => 1,
            value => 'inline',
            doc => 'lsf queue to submit the launcher or \'inline\''
        },
        job_dispatch => {
            is_constant => 1,
            is_class_wide => 1,
            value => 'inline',
            doc => 'lsf queue to submit jobs or \'inline\' to run them in the launcher'
        }
    ],
    has_param => [
        percent_overlap => 
        {
            type => 'String',
            is_optional => 1,
            doc => "this is the percent overlap, default is 50%",
        },
        percent_identity =>
        {
            type => 'String',
            is_optional => 1,
            doc => "this is the percent identity, default is 85%",
        },
        blast_params =>
        {
            type => 'String',
            is_optional => 1,
            doc => "Use this option to override the default blast params, the default param string is:\n M=1 N=-3 R=3 Q=3 W=30 wordmask=seg lcmask hspsepsmax=1000 golmax=0 B=1 V=1 topcomboN=1 -errors -notes -warnings -cpus 4 2>/dev/null",        
        }, 
    ],
    doc => "Processing Profile for the Pooled Assembly Decomposition Pipeline"
};

sub _execute_build {
    my ($self,$build) = @_;
    
    print "Executing pooled assembly decomposition build.\n";
    
    my @inputs = $build->inputs;
    my %params = map {$_->name,$_->value_id;} @inputs;

    my $data_directory = $build->data_directory;
    my $percent_identity = $self->percent_identity;
    my $percent_overlap = $self->percent_overlap;
    my $ref_seq_file = $params{ref_seq_file};
    my $pooled_assembly_dir = $params{pooled_assembly_dir};
    my $blast_params = $self->blast_params;
    my $ace_file_name = $params{ace_file_name};
    my $phd_ball_name = $params{phd_ball_name};
    
    return Genome::Model::Tools::PooledBac::Run->execute(project_dir => $data_directory, 
                                                                                      pooled_bac_dir => $pooled_assembly_dir, 
                                                                                      percent_identity => $percent_identity, 
                                                                                      percent_overlap => $percent_overlap, 
                                                                                      ref_seq_file => $ref_seq_file, 
                                                                                      blast_params => $blast_params,
                                                                                      ace_file_name => $ace_file_name,
                                                                                      phd_ball_name => $phd_ball_name,
                                                                                      );
}

1;

