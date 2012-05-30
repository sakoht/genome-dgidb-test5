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
            via => 'tumor_build',
            to => 'id',
            is_mutable => 1,
        },
        tumor_build => {
            is => 'Genome::Model::Build::ReferenceAlignment',
            via => 'inputs',
            is_many => 0,
            to => 'value',
            where => [ name => 'tumor_build', ],
            is_mutable => 1,
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
            where => [ name => 'normal_build', ],
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
        build\.xml$
        \d+\.out$
        \d+\.err$
        \.png$
        readcounts$
        variants/sv/breakdancer
        variants/sv/squaredancer
        svs\.merge\.index$
        cnv_graph\.pdf$
    );
}

sub dirs_ignored_by_diff {
    return qw(
        logs/
        variants/\d+/
        variants/sv/breakdancer
        variants/sv/squaredancer
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
    my ($self, $detector_strat, $filter_strat) = @_;

    #pull apart detector strat and then clean up the params
    my ($detector_name, $detector_version, $detector_params);

    if ($detector_strat =~ /^(\S+)\s+(\S+)/) {
        ($detector_name, $detector_version) = ($1, $2);
        if ($detector_strat =~ /\[(.+)\]/) {
            $detector_params = $1;
        }
    }
    else {
        $self->error_message("Wrong format of detector strategy: $detector_strat");
        return;
    }

    #pull apart filter strat, if it exists
    my ($filter_name, $filter_version, $filter_params);
    if ($filter_strat) {
        if ($filter_strat =~ /^(\S+)\s+(\S+)/) {
            ($filter_name, $filter_version) = ($1, $2);
            if ($filter_strat =~ /\[(.+)\]/) {
                $filter_params = $1;
            }
        }
        else {
            $self->error_message("Wrong format of filter strategy: $filter_strat");
            return;
        }
    }

    #get the class name of the detector
    $detector_name = Genome::Model::Tools::DetectVariants2::Strategy->detector_class($detector_name);

    #get the canonical paths to the whole_rmdup_bam_file's
    my $aligned_reads         = Cwd::abs_path($self->tumor_build->whole_rmdup_bam_file);
    my $control_aligned_reads = Cwd::abs_path($self->normal_build->whole_rmdup_bam_file);
    my $reference_build_id    = $self->tumor_model->reference_sequence_build_id;

    #prepare params
    my %params = (
        detector_name         => $detector_name,
        detector_version      => $detector_version,
        aligned_reads         => $aligned_reads,
        control_aligned_reads => $control_aligned_reads,
        reference_build_id    => $reference_build_id,
    );
    #add detector params if they have been specified
    $params{detector_params} = $detector_params if $detector_params;

    if ($detector_strat =~ /breakdancer/) { #assume all is wanted
        $params{chromosome_list} = 'all';
    }

    # Do not get results with the test name set... we are probably looking for "real" results.
    $params{test_name} = undef;

    #get filter class name
    if ($filter_strat){
        $filter_name = Genome::Model::Tools::DetectVariants2::Strategy->filter_class($filter_name);
        $params{filter_name}    = $filter_name;
        #$params{filter_version} = $filter_version; #somehow filter_version is not stored in SR_params now
        $params{filter_params}  = $filter_params if $filter_params;
        if ($filter_strat =~ /tigra\-/) { #assume user want all not single chr.
            $params{chromosome_list} = 'all';
        }
    }

    #determine which type of result we want, depends on whether we want a detector or a filter result
    my $result_class = $filter_strat ? 'Genome::Model::Tools::DetectVariants2::Result::Filter' : 'Genome::Model::Tools::DetectVariants2::Result';
    my @result = $result_class->get(%params);

    my $answer;

    if (scalar @result == 1) {
        $answer = $result[0]->output_dir;
    }
    elsif (scalar @result > 1) {
        $answer = join "\n", map{$_->output_dir}@result;
        $self->error_message("Got multiple results for the software result query :\n$answer");
        return;
    }
    else {
        delete $params{control_aligned_reads}; #sometimes control_aligned_reads not stored
        my @results = $result_class->get(%params);
        if (scalar @results == 1) {
            $answer = $results[0]->output_dir;
        }
        elsif (scalar @results > 1) {
            $answer = join "\n", map{$_->output_dir}@results;
            $self->error_message("Got multiple results for the software result query :\n$answer");
            return;
        }
        else {
            $self->error_message('Failed to find output path'); 
        }
    }
    return $answer;
}

sub final_result_for_variant_type {
    my $self = shift;
    my $variant_type = shift;

    my @users = Genome::SoftwareResult::User->get(user => $self);
    my @results = Genome::SoftwareResult->get([map($_->software_result_id, @users)]);
    my @dv2_results = grep($_->class =~ /Genome::Model::Tools::DetectVariants2::Result/, @results);
    @dv2_results = grep($_->class !~ /::Vcf/, @dv2_results);
    my @relevant_results = grep(scalar( @{[ glob($_->output_dir . '/' . $variant_type .'*') ]} ), @dv2_results);

    if(!@relevant_results) {
        return;
    }
    if(@relevant_results > 1) {
        die $self->error_message('Found multiple results for variant type!');
    }

    return $relevant_results[0];
}


1;
