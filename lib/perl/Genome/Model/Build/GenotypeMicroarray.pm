package Genome::Model::Build::GenotypeMicroarray;

use strict;
use warnings;

use Genome;

class Genome::Model::Build::GenotypeMicroarray {
    is => 'Genome::Model::Build',
    has => [
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
            doc => 'dbsnp build to compare against'
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

sub validate_has_reference_alignment {
    my $self = shift;
    my @tags;
    my $reference_sequence_build = $self->model->reference_sequence_build;
    unless ($reference_sequence_build) {
        push @tags, UR::Object::Tag->create(
            type => 'error',
            properties => ['reference_sequence_build'],
            desc => 'no reference_sequence_build specified for build',
        );
    }
    return @tags;

}

sub validate_for_start_methods {
    my $self = shift;
    my @methods = $self->SUPER::validate_for_start_methods();
    push @methods,
        qw/
            instrument_data_assigned
            validate_has_reference_alignment
        /;
    return @methods;
}

sub perform_post_success_actions {
    my $self = shift;
    return $self->model->request_builds_for_dependent_cron_ref_align;
}

sub copy_snp_array_file {
    my ($self, $file) = @_;

    my $formatted_genotype_file_path = $self->formatted_genotype_file_path;
    $self->status_message("Copy $file to $formatted_genotype_file_path");

    my $copy = Genome::Sys->copy_file($file, $formatted_genotype_file_path);
    if (not $copy) {
        $self->error_message("Copy failed");
        return;
    }

    if (not -s $formatted_genotype_file_path) {
        $self->error_message("Copy succeeded, but file does not exist: $formatted_genotype_file_path");
        return;
    }

    $self->status_message('Copy...OK');

    my $gold_snp_bed = $self->snvs_bed;
    my $cmd = Genome::Model::GenotypeMicroarray::Command::CreateGoldSnpBed->create(
        input_file => $file,
        output_file => $gold_snp_bed,
        reference => $self->model->reference_sequence_build,
    );
    if (!$cmd->execute) {
        $self->error_message("Failed to create Gold SNP bed file at $gold_snp_bed");
        return;
    }

    return 1;
}

sub formatted_genotype_file_path {
    shift->data_directory . '/formatted_genotype_file_path.genotype';
}

sub snvs_bed {
    shift->data_directory . '/gold_snp.v2.bed';
}

sub filtered_snvs_bed {
    shift->data_directory . '/gold_snp.v2.bed';
}

sub genotype_file_path {
    my $self = shift;
    my @instrument_data = $self->instrument_data;
    Carp::confess 'Found no instrument data for build ' . $self->id unless @instrument_data;
    Carp::confess 'Found more than one instrument data assigned to build ' . $self->id if @instrument_data > 1;
    return $instrument_data[0]->genotype_microarray_file_for_subject_and_version($self->subject_name, $self->reference_sequence_build->version);
}    

1;

