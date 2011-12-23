package Genome::Model::Tools::DetectVariants2::Classify::Tier;

use strict;
use warnings;

use File::Basename;
use Genome;

class Genome::Model::Tools::DetectVariants2::Classify::Tier {
    is => 'Genome::Model::Tools::DetectVariants2::Result::Classify',
    has_input => [
        annotation_build_id => {
            is => 'Text',
            doc => 'ID of the builds whose annotation forms the basis of tiering',
        },
    ],
    has => [
        annotation_build => {
            is => 'Genome::Model::Build::ImportedAnnotation',
            id_by => 'annotation_build_id',
        },
    ],
};

sub _validate_inputs {
    my $self = shift;

    unless($self->annotation_build) {
        $self->error_message('No annotation build found.');
        return;
    }

    my $tier_file_location = $self->annotation_build->tiering_bed_files_by_version($self->classifier_version);

    unless (-d $tier_file_location){
        die $self->error_message("Couldn't find tiering bed files from annotation build");
    }

    return $self->SUPER::_validate_inputs;
}

sub _classify_variants {
    my $self = shift;

    my $prior = $self->prior_result;
    $prior->add_user(label => 'uses', user => $self);

    my $type = $self->variant_type;
    for my $f ($type . 's.hq.bed', $type . 's.lq.bed') {
        my $file = $self->prior_result->path($f);
        next unless -e $file;
        $self->run_fast_tier($file);
    }

    return 1;
}

sub run_fast_tier {
    my $self = shift;
    my ($file) =  shift;

    my ($prefix, $suffix) = $file =~ /(.*?)\.((?:v\d+)?\.bed)/;

    my ($tier1_path, $tier2_path, $tier3_path, $tier4_path) = map {
        my $x = join('.',$prefix, 'tier' . $_, $suffix);
        my $name = File::Basename::fileparse($x);
        join('/', ($self->temp_staging_directory, $name));
    }
    (1..4);

    my %params;

    #Skip line count on fast-tiering if running on input with duplicates (lq, in this case)
    my $lq = $prefix =~ m/lq/;

    if(-s $file) {
        %params = (
            variant_bed_file => $file,
            tier_file_location => $self->annotation_build->tiering_bed_files_by_version($self->classifier_version),
            tiering_version => $self->classifier_version,
            skip_line_count => $lq,
            tier1_output => $tier1_path,
            tier2_output => $tier2_path,
            tier3_output => $tier3_path,
            tier4_output => $tier4_path,
        );
        my $tier_command = Genome::Model::Tools::FastTier::FastTier->create(%params);
        unless ($tier_command){
            die $self->error_message("Couldn't create fast tier command from params:\n" . Data::Dumper::Dumper(\%params));
        }
        my $snv_rv = $tier_command->execute;
        my $snv_err =$@;
        unless($snv_rv){
            die $self->error_message("Failed to execute fast tier command(err: $snv_err) with params:\n" . Data::Dumper::Dumper(\%params));
        }
    }else{
        $self->status_message("No detected variants for $file, skipping tiering");
        map {Genome::Sys->copy_file($file, $_)}($tier1_path, $tier2_path, $tier3_path, $tier4_path);
    }

    unless(-e "$tier1_path" and -e "$tier2_path" and -e "$tier3_path" and -e "$tier4_path"){
        die $self->error_message("SNV fast tier output not found with params:\n" . (%params?(Data::Dumper::Dumper(\%params)):''));
    }
}

sub available_versions { return (1,2,3); }

sub _needs_symlinks_followed_when_syncing { 0 };
sub _working_dir_prefix { 'dv2-tiering' };
sub resolve_allocation_disk_group_name { 'info_genome_models' };

sub resolve_allocation_subdirectory {
    my $self = shift;
    my $staged_basename = File::Basename::basename($self->temp_staging_directory);
    return join('/', 'build_merged_alignments', $self->id, 'dv2-tiering-' . $staged_basename);
};

1;
