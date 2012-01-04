package Genome::Model::Tools::DetectVariants2::VarscanSomatic;

use strict;
use warnings;

use File::Copy;
use Genome;

class Genome::Model::Tools::DetectVariants2::VarscanSomatic {
    is => ['Genome::Model::Tools::DetectVariants2::Detector'],
    has_optional => [
        params => {
            default => "--min-coverage 3 --min-var-freq 0.08 --p-value 0.10 --somatic-p-value 0.05 --strand-filter 1",
        },
    ],
    has_param => [
        lsf_resource => {
            default => "-R 'select[ncpus>=3] span[hosts=1] rusage[mem=16000]' -M 1610612736 -n 3",
        },
    ],
};


sub help_synopsis {
    return <<EOS
Runs Varscan from BAM files
EOS
}

sub help_detail {
    return <<EOS 

EOS
}

sub _detect_variants {
    my $self = shift;

    ## Get required parameters ##
    my $output_snp = $self->_temp_staging_directory."/snvs.hq";
    my $output_indel = $self->_temp_staging_directory."/indels.hq";

    unless ($self->version) {
        die $self->error_message("A version of VarscanSomatic must be specified");
    }

    my $varscan = Genome::Model::Tools::Varscan::Somatic->create(
        normal_bam => $self->control_aligned_reads_input,
        tumor_bam => $self->aligned_reads_input,,
        reference => $self->reference_sequence_input,
        output_snp => $output_snp,
        output_indel => $output_indel,
        varscan_params => $self->params,
        no_headers => 1,
        version => $self->version,
    );

    unless($varscan->execute()) {
        $self->error_message('Failed to execute Varscan: ' . $varscan->error_message);
        return;
    }

    return 1;
}

sub has_version {
    my $self = shift;
    my $version = shift;
    unless(defined($version)){
        $version = $self->version;
    }
    my @versions = Genome::Model::Tools::Varscan->available_varscan_versions;
    for my $v (@versions){
        if($v eq $version){
            return 1;
        }
    }
    return 0;  
}   

sub parse_line_for_bed_intersection {
    my $class = shift;
    my $line = shift;

    unless ($line) {
        die $class->error_message("No line provided to parse_line_for_bed_intersection");
    }

    my ($chromosome, $position, $reference, undef, $depth1, $depth2, undef, undef, undef, $qual, undef, $consensus, @extra) = split("\t", $line);

    if ($consensus =~ /-|\+/) {
        return $class->_parse_indel_for_bed_intersection($line);
    } else {
        return $class->_parse_snv_for_bed_intersection($line);
    }
}

sub _parse_indel_for_bed_intersection {
    my $class = shift;
    my $line = shift;

    my ($chromosome, $position, $_reference, undef, $depth1, $depth2, undef, undef, undef, $qual, undef, $consensus, @extra) = split("\t", $line);
    
    my @variants;
    my @indels = Genome::Model::Tools::Bed::Convert::Indel::VarscanSomaticToBed->convert_indel($line);

    for my $indel (@indels) {
        my ($reference, $variant, $start, $stop) = @$indel;
        if (defined $chromosome && defined $position && defined $reference && defined $variant) {
            push @variants, [$chromosome, $stop, $reference, $variant];
        }
    }

    unless(@variants){
        die $class->error_message("Could not get chromosome, position, reference, or variant for line: $line");
    }

    return @variants;

}

sub _parse_snv_for_bed_intersection {
    my $class = shift;
    my $line = shift;

    my ($chromosome, $position, $reference, undef, $depth1, $depth2, undef, undef, undef, $qual, undef, $consensus, @extra) = split("\t", $line);

    return [$chromosome, $position, $reference, $consensus];
}

1;
