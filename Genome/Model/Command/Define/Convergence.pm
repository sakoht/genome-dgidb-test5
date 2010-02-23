package Genome::Model::Command::Define::Convergence;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Define::Convergence {
    is => 'Genome::Model::Command::Define',
    has => [
        model_group_id => {
            is => 'Text',
            doc => 'The id of the model group for which to create a convergence model'
        },
        _model_group => {
            is => 'Genome::ModelGroup',
            id_by => 'model_group_id',
        },
    ],
    has_optional => [
        model_name => {
            is => 'Text',
            len => 255,
            doc => 'User meaningful name for this model (defaults to the model group name with "_convergence" appended',
        },
        subject_type => {
            is => 'Text',
            len => 255,
            doc => 'The type of subject all the reads originate from',
            default => 'sample_group',
        },
        processing_profile_name => {
            is => 'Text',
            doc => 'identifies the processing profile by name',
            default => 'convergence default',
        },
        subject_name => {
            is => 'Text',
            doc => 'The name of the subject the reads originate from',
        }
        
   ],
};

sub help_synopsis {
    return <<"EOS"
genome model define convergence 
  --model-group-id 242 
  --data-directory /gscmnt/somedisk/somedir/model_dir
EOS
}

sub help_detail {
    return <<"EOS"
This defines a new genome model representing the harmonic convergence analysis for a group of models.
EOS
}

sub create {
    my $class = shift;
    
    my $self = $class->SUPER::create(@_)
        or return;

    unless(defined $self->_model_group) {
        $self->error_message('No ModelGroup found for id: ' . $self->model_group_id);
        return;
    }

    unless($self->model_name) {
        $self->model_name($self->_model_group->name . '_convergence');
    }
    
    unless($self->subject_name) {
        $self->subject_name($self->_model_group->name);
    }    

    return $self;
}

sub execute {
    my $self = shift;

    $self->SUPER::_execute_body(@_) or return;

#    run Genome::Model::Command::Define execute
#    my $super = $self->super_can('_execute_body');
#    $super->($self,@_);

    # get the model created by the super
    my $model = Genome::Model->get($self->result_model_id);

    unless($model){
        $self->error_message('Could not get model from base define command.');
        return;
    }
    
    my $set_group_cmd = Genome::Model::Command::Input::Update->create(
        model_identifier => $model->id,
        name => 'group_id',
        value => $self->_model_group->id,
    );
    
    unless($set_group_cmd->execute) { 
        $self->error_message('Could not set group for model.');
        return;
    }
    
    return 1;
}

1;
