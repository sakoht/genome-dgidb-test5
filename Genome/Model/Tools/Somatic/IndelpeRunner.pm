package Genome::Model::Tools::Somatic::IndelpeRunner;

use warnings;
use strict;

use Genome;

class Genome::Model::Tools::Somatic::IndelpeRunner {

    is  => ['Command', 'Genome::Utility::FileSystem'],
    has => [
       bam_file => {
            is       => 'String',
            is_input => '1',
            doc      => 'The bam file for tumor.',
        },
       ref_seq_file => {
            is       => 'String',
            is_input => '1',
            doc      => 'The refseq fa.',
        },
        output_dir => {
            is       => 'String',
            is_input => '1',
            doc      => 'The output directory.',
        },
        snp_output_file => {
            is       => 'String',
            is_optional => '1',
            doc      => 'The snp file produced in sam snpfilter... generated with the output dir if none is provided',
        },
        filtered_snp_file => {
            is       => 'String',
            is_optional => '1',
            is_input => 1,
            is_output => '1',
            doc      => 'The filtered snp file produced in sam snpfilter... generated with the output dir if none is provided',
        },
        indel_output_file => {
            is       => 'String',
            is_optional => '1',
            doc      => 'The indel output file produced in sam snpfilter... generated with the output dir if none is provided',
        },
        filtered_indel_file => {
            is       => 'String',
            is_optional => '1',
            doc      => 'The filtered indel file produced in sam snpfilter... generated with the output dir if none is provided',
        },

       # Make workflow choose 64 bit blades
        lsf_resource => {
            is_param => 1,
            default_value => 'rusage[mem=2000] select[type==LINUX64 & mem > 2000] span[hosts=1]',
        },
        lsf_queue => {
            is_param => 1,
            default_value => 'long'
        } 
    ],
};

sub help_brief {
    return "Runs the equivalent of 'find variations' from the reference alignment pipeline to produce snp and indel files";
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
    gmt somatic indelpe-runner --bam-file=[pathname] --ref-seq-file=[pathname] --output-dir=[pathname]
EOS
}

sub help_detail {                           
    return <<EOS 
Runs the equivalent of 'find variations' from the reference alignment pipeline to produce snp and indel files
EOS
}

sub execute {
    my ($self) = @_;
    $DB::single=1;

    my $bam_file = $self->bam_file();
    
    unless(-s $bam_file) {
        $self->status_message("Bam output file $bam_file was not found or had no size.");
        die;
    }
    
    if ( ! Genome::Utility::FileSystem->validate_file_for_reading($bam_file) ) {
        $self->error_message('cant read from: ' . $bam_file);
        die;
    }

    #calling blank should return the $DEFAULT version in the G:M:T:Sam module
    my $sam_pathname = Genome::Model::Tools::Sam->path_for_samtools_version();

    # ensure the reference sequence exists.
    my $ref_seq_file = $self->ref_seq_file;
    # this might not work depending on your father and or grandfathers identity
    my $rv;
    
    my $analysis_base_path = $self->output_dir;
    unless (-d $analysis_base_path) {
        $rv = $self->create_directory($analysis_base_path);
        unless($rv) {
            $self->error_message("Failed to create directory: $analysis_base_path");
            die;
        }
        chmod 02775, $analysis_base_path;
    }

    # Generate files not provided from data directory
    unless (defined $self->snp_output_file) {
        $self->snp_output_file($self->output_dir . "/tumor_snps_from_samtools");
    }
    unless (defined $self->filtered_snp_file) {
        $self->filtered_snp_file($self->output_dir . "/filtered_tumor_snps_from_samtools");
    }
    unless (defined $self->indel_output_file) {
        $self->indel_output_file($self->output_dir . "/tumor_indels");
    }
    unless (defined $self->filtered_indel_file) {
        $self->filtered_indel_file($self->output_dir . '/filtered_tumor_indels');
    }
    
    my $snp_output_file = $self->snp_output_file;
    my $filtered_snp_file = $self->filtered_snp_file;
    my $indel_output_file = $self->indel_output_file;
    my $filtered_indel_file = $self->filtered_indel_file;

    # Skip execution if the filtered_snp_file already exists. In the somatic pipeline, if we have models that already ran through analysis we should have this file. If we have imported bams this will need to run.
    if (-s $filtered_snp_file) {
        $self->status_message("Filtered snp file $filtered_snp_file already exists. Skipping execution");
        return 1;
    }

    my $samtools_cmd = "$sam_pathname pileup -c -f $ref_seq_file";

    #Originally "-S" was used as SNP calling. In r320wu1 version, "-v" is used to replace "-S" but with 
    #double indel lines embedded, this need sanitized
    my $snp_cmd = "$samtools_cmd -v $bam_file > $snp_output_file";
    
    eval {
        $self->shellcmd(
            cmd => $samtools_cmd,
            input_files => [$bam_file],
            output_files => [$snp_output_file],
            skip_if_output_is_present => 1,
        );
    };
    if($@) {
        $self->error_message($@);
        die;
    }

    my $snp_sanitizer = Genome::Model::Tools::Sam::SnpSanitizer->create(snp_file => $snp_output_file);
    $rv = $snp_sanitizer->execute;
    unless($rv) {
        $self->error_message("Running samtools snp-sanitizer failed with exit code $rv");
        die;
    }
    
    my $indel_cmd = "$samtools_cmd -i $bam_file > $indel_output_file";
    
    eval {
        $self->shellcmd(
            cmd => $indel_cmd,
            input_files => [$bam_file],
            output_files => [$indel_output_file],
            skip_if_output_is_present => 1,
        );
    };
    if($@) {
        $self->error_message($@);
        die;
    }

    #FIXME:8-25-09 i spoke to ben and varfilter is still too permissive to be trusted so just hardcode normal snpfilter
    #in somatic pipeline until we hear different
    my $filter_type =  'SnpFilter';

    if ($filter_type =~ /^VarFilter$/i) {
        my $varfilter = Genome::Model::Tools::Sam::VarFilter->create(
            bam_file     => $bam_file,
            ref_seq_file => $ref_seq_file,
            filtered_snp_out_file   => $filtered_snp_file,
            filtered_indel_out_file => $filtered_indel_file,
        );
        $rv = $varfilter->execute;
        unless($rv) {
            $self->error_message("Running sam indel-filter failed with exit code $rv");
            die;
        }
    }
    elsif ($filter_type =~ /^SnpFilter$/i) {
        # Skip if we already have the output (often this is produced by the ReferenceAlignment pipeline--don't want to overwrite)
        unless (-s $filtered_indel_file) {
            my $indel_filter = Genome::Model::Tools::Sam::IndelFilter->create(indel_file => $indel_output_file, out_file => $filtered_indel_file);
            $rv = $indel_filter->execute;
            unless($rv) {
                $self->error_message("Running sam indel-filter failed with exit code $rv");
                die;
            }
        }
   
        my $snp_filter = Genome::Model::Tools::Sam::SnpFilter->create(
            snp_file   => $snp_output_file,
            out_file   => $filtered_snp_file,
            indel_file => $filtered_indel_file,
        );

        $rv = $snp_filter->execute;
        unless($rv) {
            $self->error_message("Running sam snp-filter failed with exit code $rv");
            die;
        }
        $self->filtered_snp_file($filtered_snp_file);
    }
    else {
        $self->error_message("Invalid variant filter type: $filter_type");
        die;
    }
    
    return 1;
} 

1;
