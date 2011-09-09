package Genome::Model::Tools::DetectVariants2::Combine::UnionSnv;

use warnings;
use strict;

use Genome;

class Genome::Model::Tools::DetectVariants2::Combine::UnionSnv{
    is => 'Genome::Model::Tools::DetectVariants2::Combine',
    doc => 'Union snvs into one file',
    has_constant => [
        _variant_type => {
            type => 'String',
            default => 'snvs',
            doc => 'variant type that this module operates on',
        },
    ],

};

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
gmt detect-variants combine --variant-file-a samtools.hq.v1.bed --variant-file-b varscan.hq.v1.bed --output-file 
EOS
}


sub _combine_variants {
    my $self = shift;
    my $snvs_a = $self->input_directory_a."/snvs.hq.bed";
    my $snvs_b = $self->input_directory_b."/snvs.hq.bed";
    my $output_file = $self->output_directory."/snvs.hq.bed";

    my @input_files = ($snvs_a, $snvs_b);

    # Using joinx with --merge-only will do a union, effectively
    my $union_command = Genome::Model::Tools::Joinx::Sort->create(
        input_files => \@input_files,
        merge_only => 1,
        output_file => $output_file,
    );
    
    unless ($union_command->execute) {
        $self->error_message("Error executing union command");
        die $self->error_message;
    }

    # When unioning, there is no "fail" really, everything should be in the hq file
    my $lq_file = $self->output_directory."/snvs.lq.bed";
    `touch $lq_file`;
    
    $self->_generate_vcf;


    return 1;
}

sub _generate_vcf {
    my $self = shift;
    my $input_a_vcf = $self->input_directory_a."/snvs.vcf";
    unless(-s $input_a_vcf){
        $self->status_message("Could not find vcf at: ".$input_a_vcf." not creating a vcf for this operation.");
        return;
    }
    my $input_b_vcf = $self->input_directory_b."/snvs.vcf";
    unless(-s $input_b_vcf){
        $self->status_message("Could not find vcf at: ".$input_b_vcf." not creating a vcf for this operation.");
        return;
    }
    my $output_file = $self->output_directory."/snvs.vcf";
    my $vcf_files;
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
    my $merge_cmd = Genome::Model::Tools::Vcf::JoinVcf->create(
        output_file => $output_file,
        vcf_file_a => $input_a_vcf,
        vcf_file_a_source => $vcf_a_source,
        vcf_file_b => $input_b_vcf,
        vcf_file_b_source => $vcf_b_source,
        intersection => 0,
    );
    unless($merge_cmd->execute){
        die $self->error_message("Could not complete merge operation.");
    }

    return 1;
}

sub get_vcf_source {
    my $self = shift;
    my $vcf = shift;

    unless(-s $vcf){
        die $self->error_message("Cannot determine the source of a file that doesn't exist...");
    }

    my $fh = Genome::Sys->open_file_for_reading($vcf);
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

1;
