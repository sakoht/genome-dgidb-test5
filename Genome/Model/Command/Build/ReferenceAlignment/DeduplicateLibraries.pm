package Genome::Model::Command::Build::ReferenceAlignment::DeduplicateLibraries;

use strict;
use warnings;

use Genome;
use Command; 

class Genome::Model::Command::Build::ReferenceAlignment::DeduplicateLibraries {
    is => ['Genome::Model::Event'],
    has => [
         disk_allocation     => {
                                calculate_from => [ 'class', 'id' ],
                                calculate => q|
                                    my $disk_allocation = Genome::Disk::Allocation->get(
                                                          owner_class_name => $class,
                                                          owner_id => $id,
                                                      );
                                    return $disk_allocation;
                                |,
        },
    ]
};

sub sub_command_sort_position { 52}

sub help_brief {
    "Merge any accumulated alignments on a model";
}

sub help_synopsis {
    return <<"EOS"
    genome-model add-reads merge-alignments --model-id 5  --ref-seq-id all_sequences
EOS
}

sub help_detail {
    return <<"EOS"
This command is launched automatically by "postprocess alignments".  

It delegates to the appropriate sub-command for the aligner
specified in the model.
EOS
}

sub command_subclassing_model_property {
    return 'rmdup_name';
}

sub is_not_to_be_run_by_add_reads {
    return 1;
}

sub resolve_accumulated_alignments_path {
    my $self = shift;

    my $build_accumulated_alignments_path = $self->build->accumulated_alignments_directory;

    if (-d $build_accumulated_alignments_path || -l $build_accumulated_alignments_path ) {
        print "$build_accumulated_alignments_path already exists as a directory or symlink, not creating an allocation";
        return $build_accumulated_alignments_path;
    }

    my $kb_needed = $self->calculate_required_disk_allocation_kb; 

    my $allocation_path = sprintf("build_merged_alignments/build%s",$self->build->id);

    my $allocation = $self->disk_allocation;

    unless ($allocation) {

        $allocation = Genome::Disk::Allocation->allocate(
                                                                  disk_group_name => 'info_genome_models',
                                                                  allocation_path => $allocation_path,
                                                                  kilobytes_requested => $kb_needed,
                                                                  owner_class_name => $self->class,
                                                                  owner_id => $self->id,
                                                                  );
        unless ($allocation) {
             $self->error_message('Failed to get disk allocation for accumulated alignments.  This dedup event needed $kb_needed kb in order to run.');
             die $self->error_message;
        }
    }

    unless (symlink($allocation->absolute_path, $build_accumulated_alignments_path)) {
            $self->error_message("Failed to symlink " . $allocation->absolute_path . " to the accumulated alignments path in the build dir."); 
            die;
    }

    return $build_accumulated_alignments_path;

}

sub calculate_required_alignment_disk_allocation_kb {
    die "abstract, must be defined in your dedup subclass!";
}
  
1;

