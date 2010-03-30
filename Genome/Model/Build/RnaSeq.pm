package Genome::Model::Build::RnaSeq;

use strict;
use warnings;

use Genome;
use File::Path 'rmtree';

class Genome::Model::Build::RnaSeq {
    is => 'Genome::Model::Build',
    is_abstract => 1,
    sub_classification_method_name => '_resolve_subclass_name',
    has => [
    ],
};

sub accumulated_alignments_directory {
    my $self = shift;
    return $self->data_directory . '/alignments';
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
    
    my $alignment_alloc = $self->accumulated_alignments_disk_allocation;
    my $alignment_path = ($alignment_alloc ? $alignment_alloc->absolute_path :  $self->accumulated_alignments_directory);
    my $fastq_directory = $self->accumulated_fastq_directory;
    my $expression_directory = $self->accumulated_expression_directory;
    
    if (!-d $alignment_path && !-l $self->accumulated_alignments_directory && !-d $fastq_directory && !-d $expression_directory) {
        $self->status_message("Nothing to do, alignment path doesn't exist and this build has no alignments symlink.  Skipping out.");
        return;
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

    if (-d $fastq_directory) {
        rmtree($fastq_directory);
        if (-d $fastq_directory) {
            $self->error_message("fastq path $fastq_directory still exists after evisceration attempt, something went wrong.");
            return;
        }
    }

    if (-d $expression_directory) {
        rmtree($expression_directory);
        if (-d $expression_directory) {
            $self->error_message("expression path $expression_directory still exists after evisceration attempt, something went wrong.");
            return;
        }
    }

    return 1;
}

sub _resolve_subclass_name { # only temporary, subclass will soon be stored
    my $class = shift;
    return __PACKAGE__->_resolve_subclass_name_by_sequencing_platform(@_);
}

sub _resolve_subclass_name_for_sequencing_platform {
    my ($class,$sequencing_platform) = @_;
    my @type_parts = split(' ',$sequencing_platform);

    my @sub_parts = map { ucfirst } @type_parts;
    my $subclass = join('',@sub_parts);

    my $class_name = join('::', 'Genome::Model::Build::RnaSeq' , $subclass);
    return $class_name;
}

sub _resolve_sequencing_platform_for_subclass_name {
    my ($class,$subclass_name) = @_;
    my ($ext) = ($subclass_name =~ /Genome::Model::Build::RnaSeq::(.*)/);
    return unless ($ext);
    my @words = $ext =~ /[a-z]+|[A-Z](?:[A-Z]+|[a-z]*)(?=$|[A-Z])/g;
    my $sequencing_platform = lc(join(" ", @words));
    return $sequencing_platform;
}


1;

