package Genome::Model::Tools::DetectVariants2::PlotCnv;

use strict;
use warnings;

use Cwd;
use Genome;

class Genome::Model::Tools::DetectVariants2::PlotCnv{
    is => ['Genome::Model::Tools::DetectVariants2::Detector'],
    has => [
        max_copy_number => {
            type => 'Number',
            is_optional => 1,
            default => 4,
            doc => 'Max copy number',
        },
        plot_ymax => {
            is => 'Number',
            is_input => 1,
            is_output => 1,
            doc => 'set the max value of the y-axis on the CN plots',
            default => '6',
        },
        bam2cn_window => {
            is => 'Number',
            is_input => 1,
            is_output => 1,
            doc => 'set the window-size used for the single-genome CN estimation',
            default => '2500',
        },
        cnvseg_markers => {
            is => 'Number',
            is_input => 1,
            is_output => 1,
            doc => 'number of consecutive markers needed to make a CN gain/loss prediction',
            default => '4',
        },
        lowres => {
            is => 'String',
            is_input => 1,
            is_output => 1,
            doc => 'Set this value to zero for higher resolution output',
            default => 1,
        },
        sex => {
            is => 'String',
            is_input => 1,
            is_output => 1,
            doc => "choose 'male' or 'female'",
            default => 'male'
        },
    ],
    has_param => [
         lsf_queue => {
             default_value => 'long',
         },
     ],
};

sub _detect_variants {
    my $self = shift;
    my $genome_build = $self->genome_build;
    my $plot_cnv_cmd = Genome::Model::Tools::CopyNumber::PlotSegmentsFromBamsWorkflow->create( 
        tumor_bam => $self->aligned_reads_input, 
        normal_bam => $self->control_aligned_reads_input,
        output_directory => $self->_temp_staging_directory,
        sex => $self->sex,
        genome_build => $genome_build,
        plot_ymax => $self->plot_ymax,
        max_copy_number => $self->max_copy_number,
        bam2cn_window => $self->bam2cn_window,
        cnvseg_markers => $self->cnvseg_markers,
        lowres => $self->lowres,
    );
    unless($plot_cnv_cmd->execute){
        $self->error_message("Failed to run PlotCnv command.");
        die $self->error_message;
    }
    my $cnvs = $self->_temp_staging_directory."/cnvs.hq";
    unless(-e $cnvs){
        system("touch $cnvs");
    }
    return 1;
}

sub has_version {
    return 1; #FIXME implement this when this module is filled out
}

# Cna current does need to sort its output (header lines being the primary problem, can probably remove them soon)
sub _sort_detector_output {
    return 1;
}

sub genome_build {
    my $self = shift;
    my $refbuild = Genome::Model::Build->get($self->reference_build_id);
    return $refbuild->version;
}

sub _generate_standard_files {
    return 1;
}

sub _create_temp_directories {
    my $self = shift;
    $self->_temp_staging_directory($self->output_directory);
    $self->_temp_scratch_directory($self->output_directory);
    return 1;
}

1;
