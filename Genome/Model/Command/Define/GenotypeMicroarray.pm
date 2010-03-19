# FIXME ebelter
# Long: remove all define modules to just have one to rule them all.
# Short: There are 2 if blocks that should have errors in them? This module builds? It shouldn't.
#
package Genome::Model::Command::Define::GenotypeMicroarray;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Define::GenotypeMicroarray {
    is => 'Genome::Model::Command::Define',
    has => [
        file => {
            is => 'Path',
            doc => 'path to the file or directory of microarray data',
        },
        no_build => {
            is => 'Boolean',
            is_optional => 1,
        },

    ],
};

sub help_synopsis {
    return <<"EOS"
genome model define genotype-microarray 
  --subject-name MY_SAMPLE
  --processing-profile-name illumina/wugc
  --file /my/snps
EOS
}

sub help_detail {
    return <<"EOS"
Define a new genome model with genotype information based on microarray data.
EOS
}

sub execute {
    my $self = shift;

    # This only needs to be done b/c we're not tracking microarray data as instrument data.
    # Once it _is_ tracked as instrument data, the normal model/build process would occur.

    $DB::single = 1;

    if (not -e $self->file) {

    }

    if (-z $self->file) {

    }

    # let the super class make the model
    my $super = $self->super_can('_execute_body');
    $super->($self,@_);
    unless ($self->result_model_id) {
        $self->error_message("Failed to define a new model: " . $self->error_message);
        return;
    }

    my $model = Genome::Model->get($self->result_model_id);
    unless ($model) {
        $self->error_message("Failed to find new model : " . $self->result_model_id);
        return;
    }

    # TODO: we should flag model types which do not do multiple builds and which should auto build when defined.
    # For now this is just handled in the command which does the model definition.

    unless ($self->no_build) {

        $self->status_message("building...\n");
        my $cmd = Genome::Model::Build::Command::Start->execute(model_identifier => $model->id);
        unless ($cmd) {
            $self->error_message("Failed to run a build on model " . $model->id . ": " . Genome::Model::Build::Command::Start->error_message);
            return;
        }

        my $build = $cmd->build;
        unless ($build) {
            $self->error_message("Failed to generate a new build for model " . $model->id . ": " . $cmd->error_message);
            return;
        }

        $self->status_message("Copying genotype data to " . $build->formatted_genotype_file_path . "...");
        Genome::Utility::FileSystem->copy_file(
            $self->file,
            $build->formatted_genotype_file_path
        );

        $build->success;
    }



    return $self;
}

1;

