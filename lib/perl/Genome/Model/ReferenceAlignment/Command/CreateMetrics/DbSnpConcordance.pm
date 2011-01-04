package Genome::Model::ReferenceAlignment::Command::CreateMetrics::DbSnpConcordance;

use strict;
use warnings;

use File::Basename;
use Genome;

my $DEFAULT_OUTPUT_SUBDIR = 'reports';

class Genome::Model::ReferenceAlignment::Command::CreateMetrics::DbSnpConcordance {
    is => 'Genome::Command::Base',
    has => [
        build => {
            doc => 'The build for which to compute dbSNP concordance',
            is => 'Genome::Model::Build::ReferenceAlignment',
            id_by => 'build_id',
            shell_args_position => 1,
        },
        build_id => {
            is => 'Integer',
            is_input => 1,
        },
    ],
    has_optional => [
        output_dir => {
            doc => "The directory to write output to (default: <build_data_dir>/$DEFAULT_OUTPUT_SUBDIR)",
            is => 'File',
            is_input => 1,
        },
        _snvs_bed => {
            is => 'File',
            doc => "instance variable: path to build's snv bed file",
        },
        _filtered_snvs_bed => {
            is => 'File',
            doc => "instance variable: path to build's filtered snv bed file",
        },
        _dbsnp_file => {
            is => 'File',
            doc => "instance variable: path to dbsnp build's snv bed file",
         },
    ],
    doc => "Compute dbSNP concordance for a build and store the resulting metrics the the database",
};

sub _verify_build_and_set_paths {
    my ($self, $build) = @_;

    $self->output_dir($build->data_directory . "/reports") if !$self->output_dir;
    $self->status_message("Results will be written to " . $self->output_dir);

    my $bname = $build->__display_name__;
    my $dbsnp_build = $build->model->dbsnp_build;
    if (!defined $dbsnp_build) {
        die "No dbsnp_build property found on build $bname.";
    }

    my $build_rsb = $build->model->reference_sequence_build;
    my $dbsnp_rsb = $dbsnp_build->model->reference;
    if (!defined $dbsnp_rsb) {
        die "DbSnp build " . $dbsnp_build->__display_name__ . " does not define a reference sequence!";
    }

    if (!$build_rsb->is_compatible_with($dbsnp_rsb)) {
        die "Build $bname has reference sequence " . $build_rsb->__display_name__ .
            " which is incompatible with " .  $dbsnp_rsb->__display_name__ . " specified by " .
            $dbsnp_build->__display_name__;
    }

    $self->_dbsnp_file($dbsnp_build->snvs_bed());
    if (!defined $self->_dbsnp_file()) {
        die "Failed to get dbsnp file from dbsnp build " . $dbsnp_build->__display_name__;
    }

    for my $type ("snvs_bed", "filtered_snvs_bed") {
        if (!$build->can($type)) {
            die "Don't know how to find snv bed file for build $bname.";
        }
        my $snv_file = $build->$type("v1");
        if (!defined $snv_file || ! -s $snv_file) {
            die "No suitable snv bed file found for build $bname [$type].";
        }
        my $propname = "_$type";
        $self->$propname($snv_file);
    }
}

sub _gen_concordance {
    my ($self, $f1, $f2, $output_path) = @_;

    my $snvcmp_cmd = Genome::Model::Tools::SnvCmp::Concordance->create(
        input_file_a => $f1,
        input_file_b => $f2,
        output_file  => $output_path,
    );
    $snvcmp_cmd->execute() or die "snvcmp failed!";
}

sub execute {
    my $self = shift;


   eval {
        $self->_verify_build_and_set_paths($self->build);

        Genome::Utility::FileSystem->create_directory($self->output_dir)
            or die "Failed to create output directory " . $self->output_dir;

        my $output_unfiltered = $self->output_dir . "/dbsnp_concordance.txt";
        my $output_filtered = $self->output_dir . "/dbsnp_concordance.filtered.txt";
        $self->_gen_concordance($self->_snvs_bed, $self->_dbsnp_file, $output_unfiltered);
        $self->_gen_concordance($self->_filtered_snvs_bed, $self->_dbsnp_file, $output_filtered);
    };
    if ($@) {
        $self->error_message($@);
        return;
    }

    return 1;
}

1;
