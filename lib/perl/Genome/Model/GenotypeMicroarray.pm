package Genome::Model::GenotypeMicroarray;

use strict;
use warnings;

use Genome;

class Genome::Model::GenotypeMicroarray{
    is => 'Genome::ModelDeprecated',
    has => [
        input_format    => { via => 'processing_profile' },
        instrument_type => { via => 'processing_profile' },
        reference_sequence_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'reference_sequence_build', value_class_name => 'Genome::Model::Build::ImportedReferenceSequence' ],
            is_many => 0,
            is_mutable => 1, # TODO: make this non-optional once backfilling is complete and reference placeholder is deleted
            is_optional => 1,
            doc => 'reference sequence to align against'
        },
        reference_sequence_build => {
            is => 'Genome::Model::Build::ImportedReferenceSequence',
            id_by => 'reference_sequence_build_id',
        },
        refseq_name => { 
            is => 'Text',
            via => 'reference_sequence_build',
            to => 'name',
        },
        refseq_version => { 
            is => 'Text',
            via => 'reference_sequence_build',
            to => 'version',
        },
        dbsnp_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'dbsnp_build', value_class_name => 'Genome::Model::Build::ImportedVariationList' ],
            is_many => 0,
            is_mutable => 1,
            is_optional => 1,
            doc => 'dbsnp build that this model is built against'
        },
        dbsnp_build => {
            is => 'Genome::Model::Build::ImportedVariationList',
            id_by => 'dbsnp_build_id',
        },
        dbsnp_version => { 
            is => 'Text',
            via => 'dbsnp_build',
            to => 'version',
        },
    ],
};

sub sequencing_platform { return 'genotype file'; }

sub is_internal { 
    my $self = shift;
    my ($instrument_data) = $self->instrument_data;
    my $source = $instrument_data->import_source_name;
    if (defined $source and $source =~ /wugc/i) {
        return 1;
    }
    return 0;
}

sub _additional_parts_for_default_name {
    my ($self, %params) = @_;
    my ($instrument_data) = $self->instrument_data;
    if ( not $instrument_data ) {
        $instrument_data = $params{instrument_data};
        if ( not $instrument_data ) {
            die 'No instrument data found for model';
        }
    }
    return ( $instrument_data->import_source_name, $instrument_data->sequencing_platform, $self->refseq_name );
}

sub dependent_cron_ref_align {
    my $self = shift;

    my @subjects = ($self->subject);
    push @subjects, Genome::Sample->get(default_genotype_data_id => [map { $_->id } $self->instrument_data]);

    my @ref_align_models = Genome::Model::ReferenceAlignment->get(
        subject_id => [map { $_->id } @subjects],
        reference_sequence_build => $self->reference_sequence_build,
        auto_assign_inst_data => 1, # our current way of saying auto-build, later to be a project relationship
    );

    # limit to models with a compatible reference sequence build
    my $gm_rsb = $self->reference_sequence_build;
    my @compatible_ref_align_models = grep {
        my $ra_rsb = $_->reference_sequence_build;
        $ra_rsb->is_compatible_with($gm_rsb);
    } @ref_align_models;

    # limit to models that either don't have a genotype_microarray_model yet or have the same genotype_microarray_model
    my @dependent_models = grep {
        my $gmm = $_->genotype_microarray_model;
        (not $gmm || ($gmm && $gmm->id == $self->id));
    } @compatible_ref_align_models;

    return @dependent_models;
}

sub request_builds_for_dependent_cron_ref_align {
    my $self = shift;
    my $sample = $self->subject;
    return 1 unless $sample->class eq 'Genome::Sample';

    for my $ref_align ($self->dependent_cron_ref_align) {
        my @lane_qc = $ref_align->get_or_create_lane_qc_models;
        for (@lane_qc) { $_->build_requested(1) };
        $ref_align->build_requested(1);
    }
    return 1;
}

1;

