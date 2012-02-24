package Genome::Model::Event::Build::ReferenceAlignment::LaneQc::CompareSnps;

use strict;
use warnings;

use Genome;
require File::Path;
use Cwd;

class Genome::Model::Event::Build::ReferenceAlignment::LaneQc::CompareSnps {
    is => [ 'Genome::Model::Event' ],
};

sub execute {
    my $self  = shift;
    my $model = $self->model;
    my $build = $self->build;

    my @instrument_data = $build->instrument_data;
    if (@instrument_data > 1) {
        my $package = __PACKAGE__;
        die $self->error_message("Build has many instrument data, $package is designed to run on a per-lane basis.");
    }

    if ( !$self->validate_gold_snp_path ) {
        # TODO why isn't this a die or a return?
        $self->status_message("No valid gold_snp_path for the build, aborting compare SNPs!");
    }

    my $output_dir = $build->qc_directory;
    File::Path::mkpath($output_dir) unless (-d $output_dir);
    unless (-d $output_dir) {
        die $self->error_message("Failed to create output_dir ($output_dir).");
    }

    my $geno_path = $self->resolve_geno_path_for_build($build);

    #TODO: Remove Over-Ambiguous Glob
    my @variant_files = glob($build->variants_directory . '/snv/samtools-*/snvs.hq');
    unless(scalar @variant_files eq 1) {
        die $self->error_message("Could not find samtools output for run.");
    }
    my $variant_file = $variant_files[0];
    unless ( -s $variant_file ) {
        die $self->error_message("Variant file missing/empty: $variant_file");
    }
    $variant_file = Cwd::abs_path($variant_file);

    my $result = Genome::Model::Tools::Analysis::LaneQc::CompareSnpsResult->get_or_create(
        genotype_file => $geno_path,
        variant_file => $variant_file,
    );
    unless ($result) {
        die $self->error_message("Failed to create Genome::Model::Tools::Analysis::LaneQc::CompareSnpsResult command.");
    }

    $result->add_user( user_id => $build->id, user_class_name => $build->class, label => 'uses' );

    die 'Missing args for creating symlink' unless $result->output_file and $build->compare_snps_file;
    Genome::Sys->create_symlink_and_log_change($self, $result->output_file, $build->compare_snps_file);

    my $metrics_rv = Genome::Model::ReferenceAlignment::Command::CreateMetrics::CompareSnps->execute(
        build_id => $self->build_id,
    );
    Carp::confess "Could not create compare_snps metrics for build " . $self->build_id unless $metrics_rv;

    return 1;
}

sub convert_feature_list_to_snp_whitelist {
    my $self = shift;
    my $feature_list = shift;
    my $output_dir = shift;

    unless ($output_dir) {
        $output_dir = $self->build->qc_directory;
    }

    my $whitelist_snps_path = "$output_dir/whitelist.txt";
    my $whitelist_snps_bed_path = "$output_dir/whitelist.bed";
    my $dump_whitelist_cmd = Genome::FeatureList::Command::DumpMergedList->create(
        feature_list => $feature_list,
        output_path => $whitelist_snps_bed_path,
    );
    unless ($dump_whitelist_cmd->execute) {
        die $self->error_message("Failed to dump feature list.");
    }

    my $whitelist_snps_bed_file = Genome::Sys->open_file_for_reading($whitelist_snps_bed_path);
    my $whitelist_snps_file = Genome::Sys->open_file_for_writing($whitelist_snps_path);
    while (my $line = $whitelist_snps_bed_file->getline) {
        $whitelist_snps_file->print((split(/\t/, $line))[3]);
    }

    if (Genome::Sys->line_count($whitelist_snps_bed_path) != Genome::Sys->line_count($whitelist_snps_path)) {
        die $self->error_message("FeatureList's BED and SNP whitelist line counts do not match.");
    }

    return $whitelist_snps_path;
}
sub resolve_geno_path_for_build {
    my $self = shift;
    my $build = shift;

    my $geno_path;
    if ($build->region_of_interest_set_name) {
        my $output_dir = $build->qc_directory;
        $geno_path = "$output_dir/geno";

        my $genotype_microarray_build = $build->genotype_microarray_build;
        my $genotype_instrument_data = $genotype_microarray_build->instrument_data;
        my $feature_list = Genome::FeatureList->get(name => $build->region_of_interest_set_name);
        my $whitelist_snps_path = $self->convert_feature_list_to_snp_whitelist($feature_list);

        my $extract_cmd = Genome::InstrumentData::Command::Microarray::Extract->create(
            variation_list_build => $build->dbsnp_build,
            instrument_data => $genotype_instrument_data,
            output => $geno_path,
            filters => ['whitelist:whitelist_snps_file=' . $whitelist_snps_path],
        );
        unless ($extract_cmd->execute) {
            die $self->error_message("Failed to extract a whitelisted genotype file.");
        }
    } else {
        $geno_path = $build->gold_snp_build->gold2geno_file_path;
    }

    unless ( -s $geno_path ) {
        die $self->error_message("Genotype file missing/empty: $geno_path");
    }

    return $geno_path;
}

sub validate_gold_snp_path {
    my $self = shift;

    my $gold_snp_path = $self->build->gold_snp_path;
    unless ($gold_snp_path and -s $gold_snp_path) {
        $self->status_message('No gold_snp_path provided for the build or it is empty');
        return;
    }

    my $head    = `head -1 $gold_snp_path`;
    my @columns = split /\s+/, $head;

    unless (@columns and @columns == 9) {
        $self->status_message("Gold snp file: $gold_snp_path is not 9-column format");
        return;
    }
    return 1;
}

1;
