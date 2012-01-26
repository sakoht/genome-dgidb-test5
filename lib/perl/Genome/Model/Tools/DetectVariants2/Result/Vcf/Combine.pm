package Genome::Model::Tools::DetectVariants2::Result::Vcf::Combine;

use strict;
use warnings;

use Genome;
use File::Copy;
use Sys::Hostname;

class Genome::Model::Tools::DetectVariants2::Result::Vcf::Combine {
    is  => ['Genome::Model::Tools::DetectVariants2::Result::Vcf'],
    has => [
        incoming_vcf_result_a => {
            is => 'Genome::Model::Tools::DetectVariants2::Result::Vcf',
            doc => 'This is the vcf-result of the first detector or filter being run on',
        },
        incoming_vcf_result_b => {
            is => 'Genome::Model::Tools::DetectVariants2::Result::Vcf',
            doc => 'This is the vcf-result of the second detector or filter being run on',
        },
        input_a_id => {
            is => 'Text',
            doc => 'ID of the first incoming software result',
        },
        input_b_id => {
            is => 'Text',
            doc => 'ID of the second incoming software result',
        },
        variant_type => {
            is => 'Text',
            valid_values => ['snv','indel'],
            doc => 'type of variants being combined',
        },
    ],
};

sub _generate_vcf {
    my $self = shift;
    my $retval=1;
    my $path = $self->input_directory;

    for my $variant_type ("snvs"){
        $self->_run_vcf_converter($variant_type);
    }

    return $retval;
}

sub _run_vcf_converter {
    my $self = shift;
    my $type = shift;

    my $input = $self->input;
    unless($input->class =~ m/Union/){
        die $self->error_message("Unioning SNV's is the only currently supported combine_vcf operation");
    }


    my $dirname = $self->output_dir;
    unless($dirname){
        die $self->error_message("Could not get dirname!");
    }
    my $output_file = $dirname . '/'.$type.'.vcf.gz';

    my $input_a_vcf = $self->incoming_vcf_result_a->output_dir."/".$type.".vcf.gz";
    my $input_b_vcf = $self->incoming_vcf_result_b->output_dir."/".$type.".vcf.gz";
    for my $input_vcf ($input_a_vcf,$input_b_vcf){
        unless(-s $input_vcf){
            $self->status_message("Skipping VCF generation, no vcf in the previous result: $input_vcf");
            return 0;
        }
    }


    my $vcf_a_source = $self->get_vcf_source($input_a_vcf);
    my $vcf_b_source = $self->get_vcf_source($input_b_vcf);
    my $source_ids;
    if($vcf_a_source =~ m/samtools/i){
        #if A has samtools, then the ordering is fine, change nothing
    } elsif ( $vcf_b_source =~ m/samtools/i) {
        #if B has samtools, swap the ordering
        ($input_a_vcf,$input_b_vcf) = ($input_b_vcf,$input_a_vcf);
        ($vcf_a_source,$vcf_b_source) = ($vcf_b_source,$vcf_a_source);
    } else {
        #if we cannot locate samtools, die
        die $self->error_message("Could not positively identify samtools input!");
    }

    my $merge_cmd = Genome::Model::Tools::Joinx::VcfMerge->create(
        input_files => [ ($input_a_vcf,$input_b_vcf)],
        output_file => $output_file,
        merge_samples => 1,
        clear_filters => 1,
        use_bgzip => 1,
        joinx_bin_path => "/usr/bin/joinx1.3",
    );

    unless($merge_cmd->execute){
        die $self->error_message("Could not complete call to gmt vcf vcf-filter!");
    }
    return 1;
}


sub get_vcf_source {
    my $self = shift;
    my $vcf = shift;

    unless(-s $vcf){
        die $self->error_message("Cannot determine the source of a file that doesn't exist...");
    }

    my $fh = Genome::Sys->open_gzip_file_for_reading($vcf);
    my $source;
    while(my $line = $fh->getline){
        chomp $line;
        if( ($line =~ m/\#\#/) && ($line =~ m/source/)) {
            (undef,$source) = split /\=/, $line;
            last;
        }
        unless( ($line =~ m/\#\#/) ){
            die $self->error_message("Could not find source tag in the header.");
        }
    }
    return $source;
}



sub _gather_params_for_get_or_create {
    my $class = shift;

    my $bx = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class, @_);

    my %params = $bx->params_list;
    my %is_input;
    my %is_param;
    my $class_object = $class->__meta__;
    for my $key ($class->property_names) {
        my $meta = $class_object->property_meta_for_name($key);
        if ($meta->{is_input} && exists $params{$key}) {
            $is_input{$key} = $params{$key};
        } elsif ($meta->{is_param} && exists $params{$key}) {
            $is_param{$key} = $params{$key};
        }
    }

    my $inputs_bx = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class, %is_input);
    my $params_bx = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class, %is_param);

    my %software_result_params = (
        params_id => $params_bx->id,
        inputs_id => $inputs_bx->id,
        subclass_name => $class,
    );

    return {
        software_result_params => \%software_result_params,
        subclass => $class,
        inputs => \%is_input,
        params => \%is_param,
    };
}

sub _validate_input {
    return 1;
}

sub _needs_symlinks_followed_when_syncing { 
    return 0;
}

sub _working_dir_prefix {
    return "detector_vcf_results";
}

sub resolve_allocation_disk_group_name { 
    return "info_genome_models";
}

sub allocation_subdir_prefix {
    return "detector_vcf_results";
}

sub _combine_variants {
    die "overload this function to do work";
}

sub estimated_kb_usage {
    return 10_000_000;
}

sub _staging_disk_usage {
    return 10_000_000;
}

sub _add_as_user_of_inputs {
    my $self = shift;

    for my $prev_vcf_result ($self->incoming_vcf_result_a,$self->incoming_vcf_result_b){
        $prev_vcf_result->add_user(user => $self, label => 'uses');
    }   

    my $input = $self->input;

    return (
        $input->add_user(user => $self, label => 'uses')
    );
}

1;
