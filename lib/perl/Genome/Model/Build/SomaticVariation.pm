package Genome::Model::Build::SomaticVariation;

use strict;
use warnings;

use Genome;
use File::Basename;

class Genome::Model::Build::SomaticVariation {
    is => 'Genome::Model::Build',
    has => [
        tumor_model => {
            is => 'Genome::Model::ReferenceAlignment',
            via => 'model',
        },
        tumor_build_id => {
            is => 'Text',
            via => 'inputs',
            to => 'value_id',
            where => [ name => 'tumor_build', value_class_name => 'Genome::Model::Build::ReferenceAlignment' ],
            is_mutable => 1,
        },
        tumor_build => {
            is => 'Genome::Model::Build::ReferenceAlignment',
            id_by => 'tumor_build_id',
        },
        normal_model => {
            is => 'Genome::Model::ReferenceAlignment',
            via => 'model',
        },
        normal_build => {
            is => 'Genome::Model::Build::ReferenceAlignment',
            via => 'inputs',
            is_many => 0,
            to => 'value',
            where => [ name => 'normal_build', value_class_name => 'Genome::Model::Build::ReferenceAlignment' ],
            is_mutable => 1,
        },
        annotation_build => {
            is => 'Genome::Model::Build::ImportedAnnotation',
            via => 'model',
        },
        previously_discovered_variations_build => {
            is => 'Genome::Model::Build::ImportedVariationList',
            via => 'model',
        },
        snv_detection_strategy => {
            is => 'Text',
            via => 'model',
        },
        sv_detection_strategy => {
            is => 'Text',
            via => 'model',
        },
        indel_detection_strategy => {
            is => 'Text',
            via => 'model',
        },
        cnv_detection_strategy => {
            is => 'Text',
            via => 'model',
        },
        tiering_version => {
            is => 'Text',
            via => 'model',
        },
        loh_version => {
            is => 'Text',
            via => 'model',
        },
   ],
};


sub create {
    my $class = shift;

    #This updates the model's tumor and normal build inputs so they are the latest complete build for copying to build inputs
    my $bx = $class->define_boolexpr(@_);
    my $model_id = $bx->value_for('model_id');
    my $model = Genome::Model->get($model_id);
    $model->update_tumor_and_normal_build_inputs;

    my $self = $class->SUPER::create(@_);

    unless ($self) {
        return;
    }
    
    $model = $self->model;
    unless ($model) {
        $self->error_message("Failed to get a model for this build!");
        return;
    }

    my $tumor_model = $model->tumor_model;
    unless ($tumor_model) {
        $self->error_message("Failed to get a tumor_model!");
        return;
    }
    
    my $normal_model = $model->normal_model;
    unless ($normal_model) {
        $self->error_message("Failed to get a normal_model!");
        return;
    }
    
    my $tumor_build = $self->tumor_build;
    unless ($tumor_build) {
        $self->error_message("Failed to get a tumor build!");
        return;
    }

    my $normal_build = $self->normal_build;
    unless ($normal_build) {
        $self->error_message("Failed to get a normal build!");
        return;
    }
    return $self;
}

sub post_allocation_initialization {
    my $self = shift;

    my @result_subfolders;
    for my $subdir ('variants', 'novel', 'effects') {
        push @result_subfolders, $self->data_directory."/".$subdir;
    }

    for my $subdir (@result_subfolders){
        Genome::Sys->create_directory($subdir) unless -d $subdir;
    }

    return 1;
}

sub tumor_bam {
    my $self = shift;
    $DB::single = 1;
    my $tumor_build = $self->tumor_build;
    my $tumor_bam = $tumor_build->whole_rmdup_bam_file;
    unless ($tumor_bam){
        die $self->error_message("No whole_rmdup_bam file found for tumor build!");
    }
    return $tumor_bam;
}

sub normal_bam {
    my $self = shift;
    my $normal_build = $self->normal_build;
    my $normal_bam = $normal_build->whole_rmdup_bam_file;
    unless ($normal_bam){
        die $self->error_message("No whole_rmdup_bam file found for normal build!");
    }
    return $normal_bam;
}

sub reference_sequence_build {
    my $self = shift;
    my $normal_build = $self->normal_build;
    my $normal_model = $normal_build->model;
    my $reference_sequence_build = $normal_model->reference_sequence_build;
    return $reference_sequence_build;
}

sub data_set_path {
    my ($self, $dataset, $version, $file_format) = @_;
    my $path;
    $version =~ s/^v//;
    if ($version and $file_format){
        $path = $self->data_directory."/$dataset.v$version.$file_format";
    }
    return $path;
}

sub calculate_estimated_kb_usage {
    my $self = shift;

    # 30 gig -- a majority of builds (using the April processing profile) end up being 15-20gig with the usual max being 25+=. Extreme maximums of 45g are noted but rare.
    return 31457280;
}

sub files_ignored_by_diff {
    return qw(
        reports/Build_Initialized/report.xml
        reports/Build_Succeeded/report.xml
        variants/dispatcher.cmd
        \.vcf$
        \.vcf.idx$
        workflow\.xml$
        \.png$
        readcounts$
        variants/sv/breakdancer
    );
}

sub dirs_ignored_by_diff {
    return qw(
        logs/
        /\d+/
        variants/sv/breakdancer
    );
}

sub workflow_instances {
    my $self = shift;
    my @instances = Workflow::Operation::Instance->get(
        name => $self->workflow_name
    );

    #older builds used a wrapper workflow
    unless(scalar @instances) {
        return $self->SUPER::workflow_instances;
    }

    return @instances;
}

sub workflow_name {
    my $self = shift;
    return $self->build_id . ' Somatic Variation Pipeline';
}

sub path_to_individual_output {
    my $self = shift;
    my $build = $self; 

    my ($detector_strat,$filter_strat) = @_;
    my ($detector_name,$detector_version, @detector_params) = split /\s+/, $detector_strat;
    my $detector_params = join(" ", @detector_params);
    my ($filter_name,$filter_version, @filter_params) = split /\s+/, $filter_strat;
    my $filter_params = join(" ", @filter_params);
    $detector_name = Genome::Model::Tools::DetectVariants2::Strategy->detector_class($detector_name);
    my %params = (
        detector_name => $detector_name,
        detector_version => $detector_version,
        aligned_reads => $build->tumor_build->whole_rmdup_bam_file,
        control_aligned_reads => $build->normal_build->whole_rmdup_bam_file,
        reference_build_id => $build->tumor_model->reference_sequence_build_id,
    );

    $params{detector_params} = $detector_params if $detector_params;

    if($filter_strat){
        $filter_name = Genome::Model::Tools::DetectVariants2::Strategy->filter_class($filter_name);
        $params{filter_name} = $filter_name;
        $params{filter_params} = $filter_params if $filter_params;
    }

    my $result_class = (defined $filter_strat) ? "Genome::Model::Tools::DetectVariants2::Result::Filter" : "Genome::Model::Tools::DetectVariants2::Result";
    my @result = $result_class->get(%params);
    my $answer = undef;
    if( scalar(@result)==1){
        $answer = $result[0]->output_dir;
    } else {
        print "Called: ".$result_class."\n";
        print "Found ".scalar(@result)."\n";;
    }
    return $answer;
}



1;
