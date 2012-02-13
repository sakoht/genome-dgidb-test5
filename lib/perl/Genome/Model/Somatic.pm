package Genome::Model::Somatic;

use strict;
use warnings;

use Genome;

class Genome::Model::Somatic {
    is  => 'Genome::ModelDeprecated',
    has => [
       only_tier_1 => { via => 'processing_profile'},
       min_mapping_quality => { via => 'processing_profile'},
       min_somatic_quality => { via => 'processing_profile'},
       skip_sv => { via => 'processing_profile'},
       require_dbsnp_allele_match => { via => 'processing_profile'},
       sv_detector_params => { via => 'processing_profile'},
       sv_detector_version => { via => 'processing_profile'},
       transcript_variant_annotator_version => { via => 'processing_profile' },
       bam_window_params => { via => 'processing_profile'},
       bam_window_version => { via => 'processing_profile'},
       sniper_params => { via => 'processing_profile'},
       sniper_version => { via => 'processing_profile'},
       bam_readcount_params => { via => 'processing_profile'},
       bam_readcount_version => { via => 'processing_profile'},
    ],
    has_optional => [
         tumor_model_links                  => { is => 'Genome::Model::Link', reverse_as => 'to_model', where => [ role => 'tumor'], is_many => 1,
                                               doc => '' },
         tumor_model                        => { is => 'Genome::Model', via => 'tumor_model_links', to => 'from_model',
                                               doc => '', },
         tumor_model_id                     => { is => 'Integer', via => 'tumor_model', to => 'id', },
         normal_model_links                 => { is => 'Genome::Model::Link', reverse_as => 'to_model', where => [ role => 'normal'], is_many => 1,
                                               doc => '' },
         normal_model                       => { is => 'Genome::Model', via => 'normal_model_links', to => 'from_model',
                                               doc => '', },
         normal_model_id                    => { is => 'Integer', via => 'normal_model', to => 'id', },
    ],
};

sub create {
    my $class = shift;
    my %params = @_;
    
    my $tumor_model_id = delete $params{tumor_model_id};
    my $tumor_model = delete $params{tumor_model};
    my $normal_model_id = delete $params{normal_model_id};
    my $normal_model = delete $params{normal_model};
    
    unless($tumor_model) {
        $tumor_model = Genome::Model->get($tumor_model_id);
        
        unless($tumor_model) {
            $class->error_message('Could not find tumor model.' );
            return;
        }
    }
    
    unless($normal_model) {
        $normal_model = Genome::Model->get($normal_model_id);
        
        unless($normal_model) {
            $class->error_message('Could not find normal model.');
            return;
        }
    }

    my $tumor_subject = $tumor_model->subject;
    my $normal_subject = $normal_model->subject;

    if($tumor_subject->can('source') and $normal_subject->can('source')) {
        my $tumor_source = $tumor_subject->source;
        my $normal_source = $normal_subject->source;
        
        if($tumor_source eq $normal_source) {
            my $subject = $tumor_source;
            
            #Set up other parameters for call to parent execute()
            $params{subject_id} = $subject->id;
            $params{subject_class_name} = $subject->class;
        } else {
            $class->error_message('Tumor and normal samples are not from same source!');
            return;
        }
    } else {
        $class->error_message('Unexpected subject for tumor or normal model!');
        return;
    }
    
    my $self = $class->SUPER::create(%params);
    
    $self->add_from_model(from_model => $normal_model, role => 'normal');
    $self->add_from_model(from_model => $tumor_model, role => 'tumor');

    return $self;
}

sub get_all_objects {
    my $self = shift;

    my @objects = $self->SUPER::get_all_objects(@_);
    my @validations = Genome::Model::VariantValidation->get(model_id=>$self->id);
    push @objects, @validations;
    return @objects;
}

1;
