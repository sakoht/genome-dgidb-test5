package Genome::Model::MetagenomicCompositionShotgun::Command::Validate;

use strict;
use warnings;
use Genome;

class Genome::Model::MetagenomicCompositionShotgun::Command::Validate {
    is => 'Genome::Command',
    doc => 'Validate MetagenomicCompositionShotgun build for QC and Metagenomic reports as well as headers.',
    has => [
        build_id => {
            is => 'Int',
        },
        report_dir => {
            is => 'Text',
            is_optional => 1,
        },
        verbose => {
            is => 'Boolean',
            is_optional => 1,
            default => 0,
        },
    ],
};

sub execute {
    my ($self) = @_;

    my $build = Genome::Model::Build->get($self->build_id);
    my $model = $build->model;

    unless ($self->report_dir){
        $self->report_dir($build->data_directory . "/reports");
    }

    my $test_bit = 0b1111; # if all tests pass result will be 1, if any fail it will be greater than 1

    # Validate BAM Headers
    $test_bit = $test_bit ^ $self->header_check();

    # Validate QC Report
    my @qc_files = ('post_trim_stats_report.tsv', 'other_stats_report.txt');
    @qc_files = map { $self->report_dir . "/$_" } @qc_files;
    $test_bit = $test_bit ^ $self->qc_check(@qc_files);

    # Validate Metagenomic Report
    my $ref_cov_report = $self->report_dir . "/metagenomic_refcov_summary.txt";
    $test_bit = $test_bit ^ $self->metagenomic_check($ref_cov_report);

    # Return
    if ($test_bit == 1) {
        $self->status_message("Passed all checks.");
    }
    else {
        $self->status_message("Failed to validate!");
    }
    print $self->bit_to_tests($test_bit) if ($self->verbose || $test_bit > 1);

    return $test_bit;
}

sub test_to_bit {
    my $self = shift;
    my $test = shift;

    if ($test eq 'Header') {
        return 0b0010;
    }
    if ($test eq 'QC') {
        return 0b0100;
    }
    if ($test eq 'Metagenomic') {
        return 0b1000;
    }
}

sub bit_to_tests {
    my $self = shift;
    my $bit = shift;

    my $pass = "PASSED:";
    my $fail = "FAILED:";

    ($bit & 0b0010) ? ($fail .= ' Header')             : ($pass .= ' Header'); 
    ($bit & 0b0100) ? ($fail .= ' QC_Report')          : ($pass .= ' QC_Report'); 
    ($bit & 0b1000) ? ($fail .= ' Metagenomic_Report') : ($pass .= ' Metagenomic_Report'); 

    return "$pass\n$fail\n";
}

sub header_check {
    my $self = shift;

    $self->expect64();

    my $flag = 0;

    my $meta_build = Genome::Model::Build->get($self->build_id);
    my $combined_bam = $meta_build->data_directory . "/reports/metagenomic_alignment.combined.bam";
    # TODO: enable once all whole_rmdup_bams are fixed.
    #my $msg = "Checking $combined_bam... ";
    #my $cmd = "samtools view -H $combined_bam | tail | grep \@RG | wc -l";
    #my $rg_count = `$cmd`;
    #if ($rg_count > 1) {
    #    $msg .= "PASS (found $rg_count read groups)";
    #    $flag = $self->test_to_bit('Header');
    #    $self->status_message($msg) if ($self->verbose);
    #}
    #else {
    #    $msg .= "FAIL (only found $rg_count read group)";
    #    $self->status_message($msg);
    #    return $flag;
    #}

    my @mga_models = $meta_build->model->_metagenomic_alignment_models;
    for my $model (@mga_models) {
        my $build = $model->last_complete_build;
        if ($build) {
            my $msg = "Checking " . $build->whole_rmdup_bam_file . "... ";
            my $cmd = "samtools view -H " . $build->whole_rmdup_bam_file . " | tail | grep \@RG | wc -l";
            my $rg_count = `$cmd`;
            if ($rg_count > 1) {
                $msg .= "PASS (found $rg_count read groups)";
                $flag = $self->test_to_bit('Header');
                $self->status_message($msg) if ($self->verbose);
            }
            else {
                $msg .= "FAIL (only found $rg_count read group)";
                $self->status_message($msg);
                return $flag;
            }
        }
    };

    return $flag;
}

sub qc_check {
    my $self = shift;
    my @files = @_;
    my $flag = 0;
    for my $file (@files) {
        my $msg = "Checking for $file... ";
        if (-s $file) {
            $msg .= "PASS";
            $flag = $self->test_to_bit('QC');
        }
        else {
            $msg .= "FAIL (empty or does not exist!)";
        }
        $self->status_message($msg) if ($self->verbose || $msg =~ /FAIL/);
    }
    return $flag;
}

sub metagenomic_check {
    my $self = shift;
    my $file = shift;

    my $flag = 0;
    my $msg = "Checking file ($file)... ";
    if (-s $file) {
        my $count = `cat $file | cut -f 4,5 | grep ^[0-9] | sort -u | wc -l`;
        if ($count > 1) {
            $msg .= "PASS";
            $flag = $self->test_to_bit('Metagenomic');
        }
        else {
            $msg .= "FAIL (possibly corrupt)";
        }
    }
    else {
        $msg .= "FAIL (empty file)";
    }
    $self->status_message($msg) if ($self->verbose || $msg =~ /FAIL/);

    return $flag;
}


sub expect64 {
    my $self = shift;
    my $uname = `uname -a`;
    unless ($uname =~ /x86_64/) {
        $self->error_message("Samtools requires a 64-bit operating system.");
        die $self->error_message;
    }
}

1;
