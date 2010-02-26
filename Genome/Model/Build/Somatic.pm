
# review gsanders jlolofie
# note: maybe calculate usage estmate instead of hardcoded value

package Genome::Model::Build::Somatic;
#:adukes this looks fine, there may be some updates required for changes to model inputs and new build protocol, ebelter will be a better judge

use strict;
use warnings;

use Genome;

class Genome::Model::Build::Somatic {
    is => 'Genome::Model::Build',
    has_optional => [
        tumor_build_links                  => { is => 'Genome::Model::Build::Link', reverse_as => 'to_build', where => [ role => 'tumor'], is_many => 1,
                                               doc => 'The bridge table entry for the links to tumor builds (should only be one)' },
        tumor_build                     => { is => 'Genome::Model::Build', via => 'tumor_build_links', to => 'from_build', 
                                               doc => 'The tumor build with which this build is associated' },
        normal_build_links                  => { is => 'Genome::Model::Build::Link', reverse_as => 'to_build', where => [ role => 'normal'], is_many => 1,
                                               doc => 'The bridge table entry for the links to normal builds (should only be one)' },
        normal_build                     => { is => 'Genome::Model::Build', via => 'normal_build_links', to => 'from_build', 
                                               doc => 'The tumor build with which this build is associated' },
    ],
};

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);

    $DB::single=1;
    unless ($self) {
        return;
    }
    my $model = $self->model;
    unless ($model) {
        $self->error_message("Failed to get a model for this build!");
        return;
    }

    my $tumor_model = $model->tumor_model;
    unless ($tumor_model) {
        $self->error_message("Failed to get a tumor_model!");
        return;
    }
    
    my $normal_model = $model->normal_model;
    unless ($normal_model) {
        $self->error_message("Failed to get a normal_model!");
        return;
    }
    
    my $tumor_build = $tumor_model->last_complete_build;
    unless ($tumor_build) {
        $self->error_message("Failed to get a tumor build!");
        return;
    }

    my $normal_build = $normal_model->last_complete_build;
    unless ($normal_build) {
        $self->error_message("Failed to get a normal build!");
        return;
    }

    $self->add_from_build(role => 'tumor', from_build => $tumor_build);
    $self->add_from_build(role => 'normal', from_build => $normal_build);
    
    return $self;
}

# Returns the newest somatic workflow instance associated with this build
# Note: Only somatic builds launched since this code was added will have workflows associated in a queryable manner
sub newest_somatic_workflow_instance {
    my $self = shift;

    my @sorted = sort {
        $b->id <=> $a->id
    } Workflow::Store::Db::Operation::Instance->get(
        name => 'Somatic Pipeline Build ' . $self->build_id
    );

    unless (@sorted) {
        $self->warning_message("No somatic workflow instances found for this build.");
        return;
    }
    
    return $sorted[0];
}

# Returns a hash ref with all of the inputs of the newest somatic workflow instance
sub somatic_workflow_inputs {
    my $self = shift;

    my $instance = $self->newest_somatic_workflow_instance;

    unless ($instance) {
        $self->error_message("no somatic workflow instance found (has build been started?)");
        $self->error_message("It is possible this build is too old to have been associated with a workflow.");
        return;
    }

    # returns hashref of workflow params like { input => value }
    return $instance->input;  
}

# Input: the name of the somatic workflow input you'd like to know
# Returns: value of one input of the latest somatic workflow instance.
# FIXME this will break if the build allocations have moved...so... if we ask the workflow for file locations perhaps we should strip off the path and instead use the build's current data_dir
# FIXME we could check to see if it changed, and if it did warn and return
sub somatic_workflow_input {
    my $self = shift;
    my $input_name = shift;

    my $input = $self->somatic_workflow_inputs;

    if ($input) {
        unless (exists $input->{$input_name}) {
            my @valid_inputs = sort(keys %$input);
            my $inputs_string = join(", ", @valid_inputs);
            $self->error_message("Input $input_name does not exist. Valid inputs to query for this build are: \n$inputs_string");
            return;
        }

        unless (defined $input->{$input_name}) {
            $self->error_message("Input $input_name exists, but is not defined for this build. Something may have gone wrong with the build.");
            return;
        }

        return $input->{$input_name};
    } else {
        my $filename = $self->data_directory . "/" . $self->old_default_filename($input_name);
        if ($filename) {
            return $filename;
        } else {
            $self->error_message("There was no workflow instance for this build and the input requested was not a filename that could be provided.");
            return;
        }
    }
}

# The intent of this method is to be capable of providing file names for older somatic builds which do not have an associated workflow
sub old_default_filename {
    my $self = shift;
    my $input_name = shift;
    
    my %default_filenames = (
        sniper_snp_output                   => 'sniper_snp_output.out',
        sniper_indel_output                 => 'sniper_indel_output.out',
        breakdancer_output_file             => 'breakdancer_output_file.out',
        breakdancer_config_file             => 'breakdancer_config_file.out',
        copy_number_output                  => 'copy_number_output.out',
        snp_filter_output                   => 'snp_filter_output.out',
        filter_ceu_yri_output               => 'filter_ceu_yri_output.out',
        adaptor_output_snp                  => 'adaptor_output_snp.out',
        dbsnp_output                        => 'dbsnp_output.out',
        loh_output_file                     => 'loh_output_file.out',
        loh_fail_output_file                => 'loh_fail_output_file.out',
        annotate_output_snp                 => 'annotate_output_snp.out',
        ucsc_output                         => 'ucsc_output.out',
        ucsc_unannotated_output             => 'ucsc_unannotated_output.out',
        ucsc_output_snp                     => 'ucsc_output.out', # redundant, but the name changed.
        ucsc_unannotated_output_snp         => 'ucsc_unannotated_output.out',
        indel_lib_filter_preferred_output   => 'indel_lib_filter_preferred_output.out',
        indel_lib_filter_single_output      => 'indel_lib_filter_single_output.out',
        indel_lib_filter_multi_output       => 'indel_lib_filter_multi_output.out',
        adaptor_output_indel                => 'adaptor_output_indel.out',
        annotate_output_indel               => 'annotate_output_indel.out',
        tier_1_snp_file                     => 'tier_1_snp_file.out',
        tier_2_snp_file                     => 'tier_2_snp_file.out',
        tier_3_snp_file                     => 'tier_3_snp_file.out',
        tier_4_snp_file                     => 'tier_4_snp_file.out',
        tier_1_indel_file                   => 'tier_1_indel_file.out',
        tier_1_snp_high_confidence_file     => 'tier_1_snp_high_confidence_file.out',
        tier_2_snp_high_confidence_file     => 'tier_2_snp_high_confidence_file.out',
        tier_3_snp_high_confidence_file     => 'tier_3_snp_high_confidence_file.out',
        tier_4_snp_high_confidence_file     => 'tier_4_snp_high_confidence_file.out',
        tier_1_indel_high_confidence_file   => 'tier_1_indel_high_confidence_file.out',
        upload_variants_snp_1_output        => 'upload_variants_snp_1_output.out',
        upload_variants_snp_2_output        => 'upload_variants_snp_2_output.out',
        upload_variants_indel_output        => 'upload_variants_indel_output.out',
        circos_graph                        => 'circos_graph.out',
        report_output                       => 'cancer_report.html',
    );

    return $default_filenames{$input_name};
}

sub calculate_estimated_kb_usage {
    my $self = shift;

    # 15 gig... overestimating by 50% or so...
    return 15728640;
}

1;
