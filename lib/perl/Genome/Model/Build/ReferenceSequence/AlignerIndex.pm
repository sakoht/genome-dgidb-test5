package Genome::Model::Build::ReferenceSequence::AlignerIndex;

use Genome;
use warnings;
use strict;
use Sys::Hostname;


class Genome::Model::Build::ReferenceSequence::AlignerIndex {
    is => ['Genome::SoftwareResult::Stageable'],

    has => [
    
        reference_build         => {
                                    is => 'Genome::Model::Build::ImportedReferenceSequence',
                                    id_by => 'reference_build_id',
                                },
        reference_name          => { via => 'reference_build', to => 'name', is_mutable => 0, is_optional => 1 },

        aligner                 => { 
                                    calculate_from => [qw/aligner_name aligner_version aligner_params/], 
                                    calculate => q|no warnings; "$aligner_name $aligner_version $aligner_params"| 
                                },
    ],
    has_input => [
        reference_build_id      => {
                                    is => 'Number',
                                    doc => 'the reference to use by id',
                                },
    ],
    has_param => [
        aligner_name            => {
                                    is => 'Text', default_value => 'maq',
                                    doc => 'the name of the aligner to use, maq, blat, newbler etc.',
                                },
        aligner_version         => {
                                    is => 'Text',
                                    doc => 'the version of the aligner to use, i.e. 0.6.8, 0.7.1, etc.',
                                    is_optional=>1,
                                },
        aligner_params          => {
                                    is => 'Text',
                                    is_optional=>1,
                                    doc => 'any additional params for the aligner in a single string',
                                },
    ],

    has_transient => [
        aligner_class_name      => {
                                    is => 'Text',
                                    is_optional => 1,
        }
    ]
};

sub _working_dir_prefix {
    "aligner-index";
}


sub required_rusage { 
    # override in subclasses
    # e.x.: "-R 'select[model!=Opteron250 && type==LINUX64] span[hosts=1] rusage[tmp=50000:mem=12000]' -M 1610612736";
    ''
}

sub aligner_requires_param_masking {
    my $class = shift;
    my $aligner_name = shift;
    
    my $aligner_class = 'Genome::InstrumentData::AlignmentResult::'  . Genome::InstrumentData::AlignmentResult->_resolve_subclass_name_for_aligner_name($aligner_name);

    # if aligner params are not required for index, and we can   generically create an index for that version, then filter it out.
    if ($aligner_class->aligner_params_required_for_index) {
        $class->status_message("This aligner does not require a parameter-specific index.");
        return 0;
    }

    return 1;
}

sub get {
    my $class = shift;
    my %p = @_;

    if ($class->aligner_requires_param_masking($p{aligner_name})) {
        $p{aligner_params} = undef; 
    }
    
    my $self = $class->SUPER::get(%p);
    return unless $self;

}


sub create { 
    my $class = shift;
    my %p = @_;
    
    my $aligner_class = 'Genome::InstrumentData::AlignmentResult::'  . Genome::InstrumentData::AlignmentResult->_resolve_subclass_name_for_aligner_name($p{aligner_name});
    $class->status_message("Aligner class name is $aligner_class");
   
    $class->status_message(sprintf("Resolved aligner class %s, making sure it's real and can be loaded.", $aligner_class)); 
    unless ($aligner_class->class) {
        $class->error_message(sprintf("Failed to load aligner class (%s).", $aligner_class));
        return;
    }
    
    if ($class->aligner_requires_param_masking($p{aligner_name})) {
        $p{aligner_params} = undef; 
    }
    
    my $self = $class->SUPER::create(%p);
    return unless $self;
    $self->aligner_class_name($aligner_class);
    
    $self->status_message("Prepare staging directories...");
    unless ($self->_prepare_staging_directory) {
        $self->error_message("Failed to prepare working directory"); 
        return;
    }

    unless ($self->_prepare_reference_index) {
        $self->error_message("Failed to prepare reference index!");
        return;
    }

    return $self;
}

sub _prepare_reference_index {
    my $self = shift;
    
    my $reference_fasta_file = sprintf("%s/all_sequences.fa", $self->reference_build->data_directory);

    unless (-s $reference_fasta_file) {
        $self->error_message(sprintf("Reference fasta file %s does not exist", $reference_fasta_file));
        return;
    }

    $DB::single = 1;
    $self->status_message(sprintf("Confirmed non-zero reference fasta file is %s", $reference_fasta_file));
    unless (symlink($reference_fasta_file, sprintf("%s/all_sequences.fa", $self->temp_staging_directory))) {
        $self->error_message("Couldn't symlink reference fasta into the staging directory");
    }

    unless ($self->aligner_class_name->prepare_reference_sequence_index($self)) {
        $self->error_message("Failed to prepare reference sequence index.");
        return;
    }

    my $output_dir = $self->output_dir || $self->_prepare_output_directory;
    $self->status_message("Alignment output path is $output_dir");

    unless ($self->_promote_data)  {
        $self->error_message("Failed to de-stage data into output path " . $self->output_dir);
        return;
    }

    $self->status_message("Prepared alignment reference index!");

    return $self;
}

# TODO push this up
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

    my %software_result_params = (params_id=>$params_bx->id,
                                  inputs_id=>$inputs_bx->id,
                                  subclass_name=>$class);
    
    return {
        software_result_params => \%software_result_params,
        subclass => $class,
        inputs=>\%is_input,
        params=>\%is_param,
    };
}

sub resolve_allocation_subdirectory {
    my $self = shift;
    my $aligner_name_tag = $self->aligner_name;
    $aligner_name_tag =~ s/[^\w]/_/g;

    my @path_components = ('model_data','ref_build_aligner_index_data',$self->reference_build->model->id,'build'.$self->reference_build->id);

    push @path_components, $aligner_name_tag;

    my $aligner_version_tag = $self->aligner_version;
    $aligner_version_tag =~ s/[^\w]/_/g;
    push @path_components, $aligner_version_tag;

    if ($self->aligner_params) {
        my $aligner_params_tag = $self->aligner_params;
        $aligner_params_tag =~ s/[^\w]/_/g;
        push @path_components, $aligner_params_tag; 
    }
        
    my $staged_basename = File::Basename::basename($self->temp_staging_directory);
    my $directory = join('/', @path_components);

    $self->status_message(sprintf("Resolved allocation subdirectory to %s", $directory));
    return $directory;
}

sub resolve_allocation_disk_group_name {
    "info_genome_models";
}

sub full_consensus_path {
    my $self = shift;
    my $extension = shift;

    return $self->output_dir . "/all_sequences." . $extension;
}




1;
