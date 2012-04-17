package Genome::Model::Event::Build::ReferenceAlignment::CoverageStats;

use strict;
use warnings;

use File::Path qw(rmtree);

use Genome;

class Genome::Model::Event::Build::ReferenceAlignment::CoverageStats {
    is => ['Genome::Model::Event'],
    has => [ ],
};

sub shortcut {
    my $self = shift;

    my %params = $self->params_for_result;
    my $result = Genome::InstrumentData::AlignmentResult::Merged::CoverageStats->get_with_lock(%params);

    if($result) {
        $self->status_message('Using existing result ' . $result->__display_name__);
        return $self->link_result_to_build($result);
    } else {
        return;
    }
}

sub execute {
    my $self = shift;
    my $build = $self->build;

    unless($self->_reference_sequence_matches) {
        die $self->error_message;
    }

    my %params = (
        $self->params_for_result,
        log_directory => $build->log_directory,
    );

    my $result = Genome::InstrumentData::AlignmentResult::Merged::CoverageStats->get_or_create(%params);

    $self->link_result_to_build($result);

    my $as_ref = $build->alignment_summary_hash_ref;
    unless ($as_ref) {
        $self->error_message('Failed to load the alignment summary metrics!');
        die($self->error_message);
    }
    my $cov_ref = $build->coverage_stats_summary_hash_ref;
    unless ($cov_ref) {
        $self->error_message('Failed to load the coverage summary metrics!');
        die($self->error_message);
    }

    return 1;
}

#TODO This should probably be moved up to __errors__ in Genome::Model::ReferenceAlignment
#but keeping it here allows the rest of the process to this point to run...
sub _reference_sequence_matches {
    my $self = shift;
    my $build = $self->build;

    my $roi_list = Genome::FeatureList->get(name => $build->region_of_interest_set_name);
    unless($roi_list) {
        die('No feature-list found for ROI: ' . $build->region_of_interest_set_name);
    }

    my $roi_reference = $roi_list->reference;
    my $reference = $self->build->reference_sequence_build;

    unless($roi_reference) {
        $self->error_message('no reference set on region of interest ' . $roi_list->name);
        return;
    }

    unless ($roi_reference->is_compatible_with($reference)) {
        if(Genome::Model::Build::ReferenceSequence::Converter->get(source_reference_build => $roi_reference, destination_reference_build => $reference)) {
            $self->status_message('Will run converter on ROI list.');
        } else {
            $self->error_message('reference sequence: ' . $reference->name . ' does not match the reference on the region of interest: ' . $roi_reference->name);
            return;
        }
    }

    return 1;
}

sub params_for_result {
    my $self = shift;
    my $build = $self->build;

    my $fl = Genome::FeatureList->get(name => $build->region_of_interest_set_name);
    unless($fl) {
        die('No feature-list found for ROI: ' . $build->region_of_interest_set_name);
    }

    my $use_short_roi = 1;
    my $short_roi_input = Genome::Model::Build::Input->get(name => 'short_roi_names', build => $build);
    if($short_roi_input) {
        $use_short_roi = $short_roi_input->value_id;
    }

    my $merge_regions = 1;
    my $merge_regions_input = Genome::Model::Build::Input->get(name => 'merge_roi_set', build => $build);
    if($merge_regions_input) {
        $merge_regions = $merge_regions_input->value_id;
    }

    my $roi_track_name_input = Genome::Model::Build::Input->get(name => 'roi_track_name', build => $build);
    my $roi_track_name;
    if ($roi_track_name_input) {
        $roi_track_name = $roi_track_name_input->value_id;
    }
    return (
        alignment_result_id => $build->merged_alignment_result->id,
        region_of_interest_set_id => $fl->id,
        minimum_depths => $build->minimum_depths,
        wingspan_values => $build->wingspan_values,
        minimum_base_quality => ($build->minimum_base_quality || 0),
        minimum_mapping_quality => ($build->minimum_mapping_quality || 0),
        use_short_roi_names => $use_short_roi,
        merge_contiguous_regions => $merge_regions,
        roi_track_name => ($roi_track_name || undef),
        test_name => ($ENV{GENOME_SOFTWARE_RESULT_TEST_NAME} || undef),
    );
}

sub link_result_to_build {
    my $self = shift;
    my $result = shift;
    my $build = $self->build;

    Genome::Sys->create_symlink($result->output_dir, $build->reference_coverage_directory);
    $result->add_user(label => 'uses', user => $build);

    return 1;
}

1;
