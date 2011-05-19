package Genome::Model::Event::Build::ReferenceAlignment::PrepareReferenceSequenceIndex;

use strict;
use warnings;

use Genome;

class Genome::Model::Event::Build::ReferenceAlignment::PrepareReferenceSequenceIndex {
    is => ['Genome::Model::Event'],
	has => [
        _calculate_total_read_count => { via => 'instrument_data'},
        #make accessors for common metrics
        (
            map {
                $_ => { via => 'metrics', to => 'value', where => [name => $_], is_mutable => 1 },
            }
            qw/total_read_count/
        ),
    ],
};

sub alignment_result_class {
    my $self = shift;
    my $model = $self->model;
    my $processing_profile = $model->processing_profile;
    my $read_aligner_name = $processing_profile->read_aligner_name;
    return 'Genome::InstrumentData::AlignmentResult::' . Genome::InstrumentData::AlignmentResult->_resolve_subclass_name_for_aligner_name($read_aligner_name);
}

sub bsub_rusage {
    my $self = shift;
    my $delegate = $self->alignment_result_class;
    my $rusage = $delegate->required_rusage_for_building_index(reference_build=>$self->model->reference_sequence_build);
    return $rusage;
}

sub metrics_for_class {
    my $class = shift;
    return();
}

sub execute {
    my $self = shift;

    return $self->_process('get_or_create');
}


sub shortcut {
    my $self = shift;

    return $self->_process('get');
}

sub _process {
    my $self = shift;
    my $mode = shift;

    $DB::single = $DB::stopper;
    
    unless (-d $self->build_directory) {
        die "Missing build directory???";
    } 

    $self->status_message(
        "Build directory: " . $self->build_directory
    );

    my $build = $self->build;
    my $model = $build->model;
    my $processing_profile = $model->processing_profile;


    my @errors;

    my %params_for_reference = (aligner_name=>$processing_profile->read_aligner_name,
                                aligner_params=>$processing_profile->read_aligner_params,
                                aligner_version=>$processing_profile->read_aligner_version,
                                reference_build=>$model->reference_sequence_build,
                                test_name=>($ENV{GENOME_SOFTWARE_RESULT_TEST_NAME} || undef));

    $self->status_message(sprintf("Finding or generating reference build index for aligner %s version %s params %s refbuild %s ",
                                                $processing_profile->read_aligner_name, $processing_profile->read_aligner_version,
                                                $processing_profile->read_aligner_params, $model->reference_sequence_build->id));
   
    my $reference_sequence_index; 
    if ($mode eq 'get_or_create') {
        $reference_sequence_index = Genome::Model::Build::ReferenceSequence::AlignerIndex->get_or_create(%params_for_reference);
        unless ($reference_sequence_index) {
            $self->error_message("Error getting or creating reference sequence index!");
            push @errors, $self->error_message;
        }
    } elsif ($mode eq 'get') {
        $reference_sequence_index = Genome::Model::Build::ReferenceSequence::AlignerIndex->get(%params_for_reference);
        unless ($reference_sequence_index) {
            return undef; 
        }
    } else {
        $self->error_message("generate alignment reference index mode unknown: $mode");
        die $self->error_message;
    }
    
    if (@errors) {
        $self->error_message(join("\n",@errors));
        return 0;
    }

    my $link = $reference_sequence_index->add_user(user => $build, label => 'uses');
    if ($link) {
        $self->status_message("Linked reference sequence index " . $reference_sequence_index->id . " to the build");
    }
    else {
        $self->error_message(
            "Failed to link the build to the reference_sequence_index " 
            . $reference_sequence_index->__display_name__ 
            . "!"
        );
        # TODO: die, but not for now
    }

    $self->status_message("Verifying...");
    unless ($self->verify_successful_completion) {
        $self->error_message("Error verifying completion!");
        return 0;
    }
    
    $self->status_message("Complete!");
    return 1;
}

sub verify_successful_completion {
    #TODO fill this in
    return 1;
}


  
1;

