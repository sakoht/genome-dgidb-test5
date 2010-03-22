package Genome::Model::RnaSeq;

use strict;
use warnings;

use Genome;

class Genome::Model::RnaSeq {
    is => 'Genome::Model',
    has => [
        dna_type                     => { via => 'processing_profile'},
        read_aligner_name            => { via => 'processing_profile'},
        read_aligner_version         => { via => 'processing_profile'},
        read_aligner_params          => { via => 'processing_profile'},
        read_trimmer_name            => { via => 'processing_profile'},
        read_trimmer_version         => { via => 'processing_profile'},
        read_trimmer_params          => { via => 'processing_profile'},
        expression_name              => { via => 'processing_profile'},
        expression_version           => { via => 'processing_profile'},
        expression_params            => { via => 'processing_profile'},
        reference_sequence_name      => { via => 'processing_profile'},
        annotation_reference_transcripts => { via => 'processing_profile'},
        alignment_events             => { is => 'Genome::Model::Event::Build::RnaSeq::AlignReads',
                                          is_many => 1,
                                          reverse_id_by => 'model',
                                          doc => 'each case of a read set being aligned to the model\'s reference sequence(s), possibly including multiple actual aligner executions',
                                     },
        alignment_file_paths         => { via => 'alignment_events' },
        build_events  => {
            is => 'Genome::Model::Event::Build',
            reverse_id_by => 'model',
            is_many => 1,
            where => [
                parent_event_id => undef,
            ]
        },
        latest_build_event => {
            calculate_from => ['build_event_arrayref'],
            calculate => q|
                my @e = sort { $a->id cmp $b->id } @$build_event_arrayref;
                my $e = $e[-1];
                return $e;
            |,
        },
        running_build_event => {
            calculate_from => ['latest_build_event'],
            calculate => q|
                # TODO: we don't currently have this event complete when child events are done.
                #return if $latest_build_event->event_status('Succeeded');
                return $latest_build_event;
            |,
        },
    ],
    doc => 'A genome model produced by aligning cDNA reads to a reference sequence.' 
};

sub reference_build {
    # we'll eventually have this return a real model build
    # for now we return an object which handles making some
    # of this API cleaner
    my $self = shift;
    unless ($self->{reference_build}) {
        my $name = $self->reference_sequence_name;
        my $build = Genome::Model::Build::ReferencePlaceholder->get($name);
        unless ($build) {
            $build = Genome::Model::Build::ReferencePlaceholder->create(
                name => $name,
                sample_type => $self->dna_type,
            );
        }
        return $self->{reference_build} = $build;
    }
    return $self->{reference_build};
}



sub build_subclass_name {
    return 'rna seq';
}

1;
