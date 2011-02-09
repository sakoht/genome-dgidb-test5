package Genome::Model::Tools::DetectVariants2::Filter::SnpFilter;

use strict;
use warnings;

use Genome;
use IO::File;

class Genome::Model::Tools::DetectVariants2::Filter::SnpFilter{
    is => ['Genome::Model::Tools::DetectVariants2::Filter'],
    doc => 'Filters out snvs that are around indels',
};

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
gmt detect-variants2 filter snp-filter
EOS
}

sub help_detail {
    return <<EOS 
Filters out snvs that are around indels
EOS
}

sub _filter_variants {
    my $self = shift;

    my $snv_input_file = $self->input_directory . "/snps_all_sequences";
    my $filtered_snv_output_file = $self->_temp_staging_directory . "/snps_all_sequences.filtered";

    # This is where samtools would have put an indel file if one was generated
    my $filtered_indel_file = $self->_get_detector_output_directory . "/indels_all_sequences.filtered";
    unless (-e $filtered_indel_file ) {
        $filtered_indel_file = $self->_generate_indels_for_filtering;
    }

    if (-s $snv_input_file) {
        my $snp_filter = Genome::Model::Tools::Sam::SnpFilter->create(
            snp_file   => $snv_input_file,
            out_file   => $filtered_snv_output_file,
            indel_file => $filtered_indel_file,
        );
        unless($snp_filter->execute) {
            $self->error_message("Running sam snp-filter failed.");
            return;
        }
    }
    else {
        #FIXME use Genome::Sys... might need to add a method there 
        `touch $filtered_snv_output_file`;
    }

    my $convert = Genome::Model::Tools::Bed::Convert::Snv::SamtoolsToBed->create( 
                source => $filtered_snv_output_file, 
                output => $self->_temp_staging_directory . "/snvs.hq.bed");

    unless($convert->execute){
        $self->error_message("Failed to convert filter output to bed.");
        die $self->error_message;
    }


    return 1;
}

sub _generate_indels_for_filtering {
    my $self = shift;

    # TODO grab samtools version and parameters by parsing the path of the input directory
    my $version = $self->_get_detector_version;
    my $parameters = $self->_get_detector_parameters;

    my $sam_pathname = Genome::Model::Tools::Sam->path_for_samtools_version($version);
    my $bam_file = $self->aligned_reads_input;
    my $ref_seq_file = $self->reference_sequence_input;
    my $samtools_cmd = "$sam_pathname pileup -c $parameters -f $ref_seq_file %s $bam_file > %s";
    
    my $indel_output_file = $self->input_directory . "/indels_all_sequences";
    my $filtered_indel_file = $self->_temp_staging_directory . "/indels_all_sequences.filtered";

    my $indel_cmd = sprintf($samtools_cmd, '-i', $indel_output_file);
    my $rv = Genome::Sys->shellcmd(
        cmd => $indel_cmd,
        input_files => [$bam_file, $ref_seq_file],
        output_files => [$indel_output_file],
        allow_zero_size_output_files => 1,
    );
    unless($rv) {
        $self->error_message("Running samtools indel failed.\nCommand: $indel_cmd");
        return;
    }

    if (-e $indel_output_file and not -s $indel_output_file) {
        $self->warning_message("No indels detected.");
    }

    if (-s $indel_output_file) {
        my %indel_filter_params = ( indel_file => $indel_output_file, out_file => $filtered_indel_file );
        # for capture data we do not know the proper ceiling for depth
        if ($self->capture_set_input) {
            $indel_filter_params{max_read_depth} = 1000000;
        }
        my $indel_filter = Genome::Model::Tools::Sam::IndelFilter->create(%indel_filter_params);
        unless($indel_filter->execute) {
            $self->error_message("Running sam indel-filter failed.");
            return;
        }
    }
    else {
        Genome::Sys->write_file($filtered_indel_file);
    }


    return $filtered_indel_file;
}

1;
