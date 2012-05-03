package Genome::Model::Build::RnaSeq;

use strict;
use warnings;

use Genome;
use File::Path 'rmtree';

class Genome::Model::Build::RnaSeq {
    is => 'Genome::Model::Build',
    has => [
        annotation_build => {
            is => "Genome::Model::Build::ImportedAnnotation",
            is_input => 1
        },
        reference_sequence_build => {
            is => "Genome::Model::Build::ReferenceSequence",
            is_input => 1
        },
    ]
};

sub accumulated_alignments_directory {
    my $self = shift;
    return $self->data_directory . '/alignments';
}

sub coverage_directory {
    my $self = shift;
    return $self->data_directory . '/coverage';
}

sub metrics_directory {
    my $self = shift;
    return $self->data_directory . '/metrics';
}

sub picard_rna_seq_ribo_intervals {
    my $self = shift;
    return $self->metrics_directory .'/Picard_ribo.intervals';
}

sub picard_rna_seq_mRNA_ref_flat {
    my $self = shift;
    return $self->metrics_directory .'/Picard_mRNA.refFlat';
}

sub picard_rna_seq_metrics {
    my $self = shift;
    return $self->metrics_directory .'/PicardRnaSeqMetrics.txt';
}

sub picard_rna_seq_chart {
    my $self = shift;
    return $self->metrics_directory .'/PicardRnaSeqChart.pdf';
}

sub picard_rna_seq_pie_chart {
    my $self = shift;
    return $self->metrics_directory .'/PicardRnaSeqMetrics.png';
}

sub accumulated_alignments_disk_allocation {
    my $self = shift;

    my $align_event = Genome::Model::Event::Build::RnaSeq::AlignReads->get(
        model_id=>$self->model->id,
        build_id=>$self->build_id
    );

    return if (!$align_event);

    my $disk_allocation = Genome::Disk::Allocation->get(owner_class_name=>ref($align_event), owner_id=>$align_event->id);

    return $disk_allocation;
}

sub accumulated_fastq_directory {
    my $self = shift;
    return $self->data_directory . '/fastq';
}

sub accumulated_expression_directory {
    my $self = shift;
    return $self->data_directory . '/expression';
}

sub alignment_result {
    my $self = shift;

    my @u = Genome::SoftwareResult::User->get(user_id => $self->build_id);
    my $alignment_class = Genome::InstrumentData::AlignmentResult->_resolve_subclass_name_for_aligner_name($self->processing_profile->read_aligner_name);
    my $alignment = join('::', 'Genome::InstrumentData::AlignmentResult', $alignment_class)->get([map($_->software_result_id, @u)]);
    return $alignment;
}

sub alignment_result_with_lock {
    my $self = shift;

    return $self->_fetch_alignment_result('get_with_lock');
}

sub generate_alignment_result {
    my $self = shift;

    return $self->_fetch_alignment_result('get_or_create');
}

sub _fetch_alignment_result {
    my $self = shift;
    my $mode = shift;

    my @instrument_data_inputs = $self->instrument_data_inputs;
    my ($params) = $self->model->params_for_alignment(@instrument_data_inputs);

    my $alignment_class = Genome::InstrumentData::AlignmentResult->_resolve_subclass_name_for_aligner_name($self->model->read_aligner_name);
    my $alignment = join('::', 'Genome::InstrumentData::AlignmentResult', $alignment_class)->$mode(
        %$params,
    );

    return $alignment;
}

sub delete {
    my $self = shift;
    
    # if we have an alignments directory, nuke it first since it has its own allocation
    if (-e $self->accumulated_alignments_directory || -e $self->accumulated_fastq_directory || -e $self->accumulated_expression_directory) {
        unless($self->eviscerate()) {
            my $eviscerate_error = $self->error_message();
            $self->error_message("Eviscerate failed: $eviscerate_error");
            return;
        };
    }
    
    $self->SUPER::delete(@_);
}

# nuke the accumulated alignment directory
sub eviscerate {
    my $self = shift;
    
    $self->status_message('Entering eviscerate for build:' . $self->id);


    if($self->alignment_result) {
        my $alignment_result = $self->alignment_result;

        if (-l $self->accumulated_alignments_directory && readlink($self->accumulated_alignments_directory) eq $alignment_result->output_dir) {
           $self->status_message("Unlinking symlink to alignment result: " . $self->accumulated_alignments_directory);
            unless(unlink($self->accumulated_alignments_directory)) {
                $self->error_message("could not remove symlink to alignment result path");
                return;
            }
        }

        my @users = $alignment_result->users(user => $self);
        map($_->delete, @users);
        $self->status_message('Removed self as user of alignment result.');
    } else {
        my $alignment_alloc = $self->accumulated_alignments_disk_allocation;
        my $alignment_path = ($alignment_alloc ? $alignment_alloc->absolute_path :  $self->accumulated_alignments_directory);

        if (!-d $alignment_path && !-l $self->accumulated_alignments_directory) {
            $self->status_message("Nothing to do, alignment path doesn't exist and this build has no alignments symlink.");
        }

        $self->status_message("Removing tree $alignment_path");
        if (-d $alignment_path) {
            rmtree($alignment_path);
            if (-d $alignment_path) {
                $self->error_message("alignment path $alignment_path still exists after evisceration attempt, something went wrong.");
                return;
            }
        }

        if ($alignment_alloc) {
            unless ($alignment_alloc->deallocate) {
                $self->error_message("could not deallocate the alignment allocation.");
                return;
            }
        }

        if (-l $self->accumulated_alignments_directory && readlink($self->accumulated_alignments_directory) eq $alignment_path ) {
            $self->status_message("Unlinking symlink: " . $self->accumulated_alignments_directory);
            unless(unlink($self->accumulated_alignments_directory)) {
                $self->error_message("could not remove symlink to deallocated accumulated alignments path");
                return;
            }
        }
    }

    my $fastq_directory = $self->accumulated_fastq_directory;
    my $expression_directory = $self->accumulated_expression_directory;

    if (-d $fastq_directory) {
        $self->status_message('removing fastq directory');
        rmtree($fastq_directory);
        if (-d $fastq_directory) {
            $self->error_message("fastq path $fastq_directory still exists after evisceration attempt, something went wrong.");
            return;
        }
    }

    if (-d $expression_directory) {
        $self->status_message('removing expression directory');
        rmtree($expression_directory);
        if (-d $expression_directory) {
            $self->error_message("expression path $expression_directory still exists after evisceration attempt, something went wrong.");
            return;
        }
    }

    return 1;
}

sub workflow_name {
    my $self = shift;
    return $self->build_id;
}

sub workflow_instances {
    my $self = shift;

    my @instances = $self->SUPER::workflow_instances;

    unless(@instances) {
        @instances = Workflow::Operation::Instance->get(
            name => $self->SUPER::workflow_name, #older profiles were staged
        );
    }
    return @instances;
}

sub ensure_annotation_build_provided {
    my $self = shift;
    my @tags = ();
    unless ( ($self->model->annotation_reference_transcripts_mode eq 'de novo') or $self->annotation_build ) {
        push @tags, UR::Object::Tag->create(
            type => 'invalid',
            properties => [qw/ annotation_build /],
            desc => "Processing Profile calls for " . $self->model->annotation_reference_transcripts_mode . " mode, but this model does not have an annotation_build set",
        );
    }
    return @tags;
}

sub validate_for_start_methods {
    my $self = shift;
    my @methods = $self->SUPER::validate_for_start_methods;
    push @methods, 'ensure_annotation_build_provided';
    return @methods;
}

1;

