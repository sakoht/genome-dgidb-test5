package Genome::Model::SomaticVariation::Command::IdentifyPreviouslyDiscoveredVariations;

use strict;
use warnings;
use Genome;

class Genome::Model::SomaticVariation::Command::IdentifyPreviouslyDiscoveredVariations{
    is => 'Genome::Command::Base',
    has =>[
        build_id => {
            is => 'Integer',
            is_input => 1,
            is_output => 1,
            doc => 'build id of SomaticVariation model',
        },
        build => {
            is => 'Genome::Model::Build::SomaticVariation',
            id_by => 'build_id',
        }
    ],
    has_param => [
        lsf_queue => {
            default => 'apipe',
        },
    ],
};

sub execute{
    my $self  = shift;
    my $build = $self->build;
    unless ($build) {
        die $self->error_message("no build provided!");
    }


    $self->status_message("Comparing detected variants to previously discovered variations");

    my ($snv_result, $indel_result, $skip_flag);

    my $prev_variations_build = $build->previously_discovered_variations_build;
    unless ($prev_variations_build) {
        $self->warning_message('No previously_discovered_variations_build provided !');
        $skip_flag = 1;
    }


    unless ($skip_flag) {
        $snv_result   = $prev_variations_build->snv_result;
        $indel_result = $prev_variations_build->indel_result;

        unless ($indel_result or $snv_result) {
            die $self->error_message("No indel or snv result found on previously discovered variations build. This is unsupported!  Failing.");
        }
    }

    my $version = 2;
    #my $version = GMT:BED:CONVERT::version();  TODO, something like this instead of hardcoding

    if ($build->snv_detection_strategy){
        my $detected_snv_path = defined($build->loh_version) ? $build->data_set_path("loh/snvs.somatic",$version,'bed') : $build->data_set_path("variants/snvs.hq",$version,"bed"); 
        my $novel_detected_snv_path = $build->data_set_path("novel/snvs.hq.novel",$version,'bed');
        my $previously_detected_snv_path = $build->data_set_path("novel/snvs.hq.previously_detected",$version,'bed');

        if ($snv_result) {
            my $snv_result_path = join('/', $snv_result->output_dir, 'snvs.hq.bed');

            unless (-e $snv_result_path){
                die $self->error_message("Snv feature list does not have an associated file!");
            }

            unless (-e $detected_snv_path){
                die $self->error_message("No high confidence detected snvs to filter against previously discovered variants");
            }

            if (-s $detected_snv_path){ 
                my $snv_output_tmp_file = Genome::Sys->create_temp_file_path();
                my $previously_detected_output_tmp_file = Genome::Sys->create_temp_file_path();
                my $snv_compare = Genome::Model::Tools::Joinx::Intersect->create(
                    input_file_a => $detected_snv_path,
                    input_file_b => $snv_result_path,
                    miss_a_file => $snv_output_tmp_file,
                    output_file => $previously_detected_output_tmp_file,
                    dbsnp_match => 1,
                );
                unless ($snv_compare){
                    die $self->error_message("Couldn't create snv comparison tool!");
                }
                my $snv_rv = $snv_compare->execute();
                my $snv_err = $@;
                unless ($snv_rv){
                    die $self->error_message("Failed to execute snv comparison(err: $snv_err )");
                }
                $self->status_message("Intersection against previously discovered snv feature list complete");
                File::Copy::copy($snv_output_tmp_file, $novel_detected_snv_path);
                File::Copy::copy($previously_detected_output_tmp_file, $previously_detected_snv_path);
            }
            else{
                $self->status_message("high confidence snv output is empty, skipping intersection");
                Genome::Sys->create_directory($build->data_directory."/novel");
                File::Copy::copy($detected_snv_path, $novel_detected_snv_path);
                File::Copy::copy($detected_snv_path, $previously_detected_snv_path);
            }
        }
        else{
            $self->status_message("No snv feature list found on previously discovered variations build, skipping snv intersection");
            File::Copy::copy($detected_snv_path, $novel_detected_snv_path);
            system("touch $previously_detected_snv_path");
        }
    }

    if ($build->indel_detection_strategy) {
        my $detected_indel_path            = $build->data_set_path("variants/indels.hq",$version,"bed"); 
        my $novel_detected_indel_path      = $build->data_set_path("novel/indels.hq.novel",$version,"bed");
        my $previously_detected_indel_path = $build->data_set_path("novel/indels.hq.previously_detected", $version, "bed");

        if ($indel_result) {
            my $indel_result_path = join('/', $indel_result->output_dir, 'indels.hq.bed');

            unless (-e $indel_result_path){
                die $self->error_message("Indel feature list does not have an associated file!");
            }

            unless (-e $detected_indel_path){
                die $self->error_message("No high confidence detected indels to filter against previously discovered variants");
            }

            if (-s $detected_indel_path){ 
                my $indel_output_tmp_file = Genome::Sys->create_temp_file_path();
                my $previously_detected_output_tmp_file = Genome::Sys->create_temp_file_path();
                my $indel_compare = Genome::Model::Tools::Joinx::Intersect->create(
                    input_file_a => $detected_indel_path,
                    input_file_b => $indel_result_path,
                    miss_a_file => $indel_output_tmp_file,
                    output_file => $previously_detected_output_tmp_file,
                    exact_allele => 1,
                );
                unless ($indel_compare){
                    die $self->error_message("Couldn't create indel comparison tool!");
                }
                my $indel_rv = $indel_compare->execute();
                my $indel_err = $@;
                unless ($indel_rv){
                    die $self->error_message("failed to execute indel comparison(err: $indel_err )");
                }
                $self->status_message("intersection against previously discovered indel feature list complete");
                File::Copy::copy($indel_output_tmp_file, $novel_detected_indel_path);
                File::Copy::copy($previously_detected_output_tmp_file, $previously_detected_indel_path);
            }
            else{
                $self->status_message("high confidence indel output is empty, skipping intersection");
                Genome::Sys->create_directory($build->data_directory."/novel");
                File::Copy::copy($detected_indel_path, $novel_detected_indel_path);
                File::Copy::copy($detected_indel_path, $previously_detected_indel_path);
            }
        }
        else{
            $self->status_message("No indel feature list found on previously discovered variations build, skipping indel intersection");
            File::Copy::copy($detected_indel_path, $novel_detected_indel_path);
            system("touch $previously_detected_indel_path");
        }
    }

    $self->status_message("Identify Previously Discovered Variations step completed");
    return 1;
}

1;

