package Genome::InstrumentData;

use strict;
use warnings;

use Genome;

class Genome::InstrumentData {
    is => 'Genome::Notable',
    is_abstract => 1,
    subclassify_by => 'subclass_name',
    subclass_description_preprocessor => __PACKAGE__ . '::_preprocess_subclass_description',
    attributes_have => [
        is_attribute => { is => 'Boolean', is_optional => 1, },
    ],
    id_by => [
        id => { is => 'Text' },
    ],
    has => [
        seq_id => { calculate_from => [ 'id' ], calculate => q{ return $id }, },
        subclass_name => { is => 'Text' },
        sequencing_platform => { is => 'Text' },
        library => { is => 'Genome::Library', id_by => 'library_id' },
        library_name => { via => 'library', to => 'name' },
        sample_id => { is => 'Number', is_delegated => 1, via => 'library', to => 'sample_id' },
        sample => { is => 'Genome::Sample', id_by => 'sample_id' },
        sample_name => { via => 'sample', to => 'name' },
    ],
    has_optional => [
        #TODO: may want to make these immutable, but needed them for
        #backfilling purposes
        original_est_fragment_size => {
            is => 'Number',
            is_mutable => 1,
            via => 'attributes',
            to => 'attribute_value',
            where => [attribute_label => 'original_est_fragment_size'],
        },
        original_est_fragment_size_max => {
            is => 'Number',
            is_mutable => 1,
            via => 'attributes',
            to => 'attribute_value',
            where => [attribute_label => 'original_est_fragment_size_max'],
        },
        original_est_fragment_size_min => {
            is => 'Number',
            is_mutable => 1,
            via => 'attributes',
            to => 'attribute_value',
            where => [attribute_label => 'original_est_fragment_size_min'],
        },
        original_est_fragment_std_dev => {
            is => 'Number',
            is_calculated => 1,
            calculate_from => ['original_est_fragment_size_max', 'original_est_fragment_size_min'],
            calculate => q|($original_est_fragment_size_max - $original_est_fragment_size_min)/6|,
        },
        final_est_fragment_size => {
            is => 'Number',
            is_mutable => 1,
            via => 'attributes',
            to => 'attribute_value',
            where => [attribute_label => 'final_est_fragment_size'],
        },
        final_est_fragment_std_dev => {
            is => 'Number',
            is_calculated => 1,
            calculate_from => ['final_est_fragment_size'],
            calculate => q|$final_est_fragment_size*.05|,
        },
        read_orientation => {
            is => 'Text',
            is_mutable => 1,
            via => 'attributes',
            to => 'attribute_value',
            where => [attribute_label => 'read_orientation'],
            valid_values => [qw(forward_reverse reverse_forward)],
        },
        run_name => { is => 'Text' },
        subset_name => { is => 'Text' },
        full_name => {
            calculate_from => ['run_name','subset_name'],
            calculate => q|"$run_name/$subset_name"|,
        },
        full_path => {
            is => 'Text',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [ attribute_label => 'full_path' ],
        },
        ignored => {
            is => 'Number',
            via => 'attributes',
            to => 'attribute_value',
            is_mutable => 1,
            where => [attribute_label => 'ignored'],
            default => '0',
        },
        sample_source => { via => 'sample', is => 'Genome::Subject', to => 'source' },
        sample_source_id => { via => 'sample_source', to => 'id' },
        sample_source_name => { via => 'sample_source', to => 'name' },
        taxon => { is => 'Genome::Taxon', via => 'sample' },
        species_name => { via => 'taxon' },
    ],
    has_many_optional => [
        attributes => {
            is => 'Genome::InstrumentDataAttribute',
            reverse_as => 'instrument_data',
        },
        events => {
            is => 'Genome::Model::Event',
            reverse_id_by => "instrument_data"
        },
        allocations => {
            is => 'Genome::Disk::Allocation',
            reverse_as => 'owner',
        },
    ],
    table_name => 'INSTRUMENT_DATA',
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
    doc => 'Contains information common to all types of instrument data',
};

sub _preprocess_subclass_description {
    my ($class, $desc) = @_;

    for my $prop_name ( keys %{$desc->{has}} ) {
        my $prop_desc = $desc->{has}{$prop_name};
        next if not $prop_desc->{is_attribute};
        $prop_desc->{via} = 'attributes';
        $prop_desc->{where} = [ attribute_label => $prop_name ];
        $prop_desc->{to} = 'attribute_value';
        $prop_desc->{is_delegated} = 1;
        $prop_desc->{is_mutable} = 1;
    }

    return $desc;
}

sub create {
    my ($class) = @_;
    if ($class eq __PACKAGE__ or $class->__meta__->is_abstract) {
        # this class is abstract, and the super-class re-calls the constructor from the correct subclass
        return $class->SUPER::create(@_);
    }

    # This extra processing allows for someone to create instrument data with properties that aren't listed in any of the
    # class definitions. Instead of having UR catch these extras and die, they are captured here and later turned into
    # instrument data attributes.
    $class = shift;
    my ($bx, @extra);
    eval{ ($bx, @extra) = $class->define_boolexpr(@_); };
    return if not $bx;
    @extra = grep { defined } @extra;
    if ( @extra and @extra % 2 == 1 ) {
        $class->error_message("Odd number of attributes sent to create intrument data: ".Data::Dumper::Dumper(\@extra));
        return;
    }

    my $self = $class->SUPER::create($bx);
    return if not $self;

    for ( my $i = 0; $i <= @extra - 1; $i += 2 ) {
        my $attribute = Genome::InstrumentDataAttribute->create(
            attribute_label => $extra[$i],
            attribute_value => $extra[$i + 1],
            instrument_data_id => $self->id,
        );
        unless ($attribute) {
            $self->error_message("Could not create attribute ".$extra[$i]." => " . $extra[$i + 1] . " for instrument data " . $self->id);
            $self->delete;
            return;
        }
    }

    return $self;
}

sub delete {
    my $self = shift;

    my ($expunge_status) = $self->_expunge_assignments;
    return unless $expunge_status;

    #finally, clean up the instrument data
    for my $attr ( $self->attributes ) {
        $attr->delete;
    }

    $self->_create_deallocate_observer;

    for my $attribute ($self->attributes) {
        $attribute->delete;
    }

    return $self->SUPER::delete;
}

sub _expunge_assignments{
    my $self = shift;
    my $instrument_data_id = $self->id;
    my %affected_users;

    my @inputs = Genome::Model::Input->get(
        name => 'instrument_data',
        value_id => $instrument_data_id
    );
    my @models = map( $_->model, @inputs);

    for my $model (@models) {
        $model->remove_instrument_data($self);
        my $display_name = $self->__display_name__;
        push(@{$affected_users{$model->user_name}->{join(" ", $display_name, $self->id)}}, $model->id);
    }

    # There may be builds using this instrument data even though it had previously been unassigned from the model
    my @build_inputs = Genome::Model::Build::Input->get(
        name => 'instrument_data',
        value_id => $instrument_data_id
    );
    my @builds = map($_->build, @build_inputs);
    for my $build (@builds) {
        $build->abandon();
        push @models, $build->model;
    }

    my @merged_results = Genome::InstrumentData::AlignmentResult::Merged->get(instrument_data_id => $self->id);
    for my $merged_result (@merged_results) {
        unless ($merged_result->delete) {
            die $self->error_message("Could not remove instrument data " . $self->__display_name__ .
                " because merged alignment result " . $merged_result->__display_name__ .
                " that uses this instrument data could not be deleted!");
        }
    }

    my @alignment_results = Genome::InstrumentData::AlignmentResult->get(instrument_data_id => $self->id);
    for my $alignment_result (@alignment_results) {
        unless($alignment_result->delete){
            die $self->error_message("Could not remove instrument data " . $self->__display_name__ . " because it has " .
            " an alignment result (" . $alignment_result->__display_name__ . ") that could not be deleted!");
        }
    }

    return 1, %affected_users;
}

sub _create_deallocate_observer {
    my $self = shift;
    my @allocations = $self->allocations;
    return 1 unless @allocations;
    my $deallocator;
    $deallocator = sub {
        for my $allocation (@allocations) {
            $allocation->delete;
        }
        UR::Context->cancel_change_subscription(
            'commit', $deallocator
        );
    };
    UR::Context->create_subscription(
        method => 'commit',
        callback => $deallocator
    );
    return 1;
}

sub calculate_alignment_estimated_kb_usage {
    my $self = shift;
    Carp::confess "calculate_alignment_estimated_kb_usage not overridden in instrument data subclass " . $self->class;
}

sub sample_type {
    my $self = shift;
    my $sample_extraction_type = $self->sample->extraction_type;
    return unless defined $sample_extraction_type;

    if ($sample_extraction_type eq 'genomic_dna' or $sample_extraction_type eq 'pooled dna') {
        return 'dna';
    }
    elsif ($sample_extraction_type eq 'rna') {
        return 'rna';
    }
    return;
}

sub create_mock {
    my $class = shift;
    return $class->SUPER::create_mock(subclass_name => 'Genome::InstrumentData', @_);
}

sub run_identifier  {
    die "run_identifier not defined in instrument data subclass.  please define this. this method should " .
         "provide a unique identifier for the experiment/run (eg flow_cell_id, ptp barcode, etc).";
}

sub dump_fastqs_from_bam {
    my $self = shift;
    my %p = @_;

    die "cannot call bam path" if (!$self->can('bam_path'));

    unless (-e $self->bam_path) {
        $self->error_message("Attempted to dump a bam but the path does not exist:" . $self->bam_path);
        die $self->error_message;
    }

    my $directory = delete $p{directory};
    $directory ||= Genome::Sys->create_temp_directory('unpacked_bam_'.$self->id);

    my $subset = (defined $self->subset_name ? $self->subset_name : 0);

    my %read_group_params;

    if (defined $p{read_group_id}) {
        $read_group_params{read_group_id} = delete $p{read_group_id};
        $self->status_message("Using read group id " . $read_group_params{read_group_id});
    }

    my $fwd_file = sprintf("%s/s_%s_1_sequence.txt", $directory, $subset);
    my $rev_file = sprintf("%s/s_%s_2_sequence.txt", $directory, $subset);
    my $fragment_file = sprintf("%s/s_%s_sequence.txt", $directory, $subset);
    my $cmd = Genome::Model::Tools::Picard::SamToFastq->create(input=>$self->bam_path, fastq=>$fwd_file, fastq2=>$rev_file, fragment_fastq=>$fragment_file, no_orphans=>1, %read_group_params);
    if ( not $cmd ) {
        die $self->error_message('Failed to create gmt picard sam-to-fastq');
    }
    $cmd->dump_status_messages(1);
    unless ($cmd->execute()) {
        die $cmd->error_message;
    }

    if ((-s $fwd_file && !-s $rev_file) ||
        (!-s $fwd_file && -s $rev_file)) {
        $self->error_message("Fwd & Rev files are lopsided; one has content and the other doesn't. Can't proceed");
        die $self->error_message;
    }

    my @files;
    if (-s $fwd_file && -s $rev_file) {
        push @files, ($fwd_file, $rev_file);
    }
    if (-s $fragment_file && !$p{discard_fragments}) {
        push @files, $fragment_file;
    }

    return @files;
}

sub lane_qc_models {
    my $self = shift;

    # Find the Lane QC models that use this instrument data
    my $instrument_data_id = $self->id;
    my @inputs = Genome::Model::Input->get(value_id => $instrument_data_id);
    my @lane_qc_models = grep { $_->is_lane_qc }
                         grep { $_->class eq 'Genome::Model::ReferenceAlignment' }
                         map  { $_->model } @inputs;

    # Find the Lane QC models that used the default genotype_microarray input
    my $sample = $self->sample;
    my @gm_model_ids = map { $_->id } ($sample->default_genotype_models);
    @lane_qc_models = grep { $_->inputs(name => 'genotype_microarray', value_id => \@gm_model_ids) } @lane_qc_models;

    return @lane_qc_models;;
}

sub lane_qc_build {
    my $self = shift;
    my @qc_models = $self->lane_qc_models;
    return unless @qc_models;
    my @builds = sort { $b->id <=> $a->id } map { $_->succeeded_builds } @qc_models;
    return unless @builds;
    return $builds[0];
}

sub lane_qc_dir {
    my $self = shift;
    my $qc_build = $self->lane_qc_build;
    return unless ($qc_build);
    my $qc_dir = $qc_build->qc_directory;
    if (-d $qc_dir) {
        return $qc_dir;
    }
    else {
        return;
    }
}


sub __display_name__ {
    my $self = shift;
    my $subset_name = $self->subset_name || 'unknown-subset';
    my $run_name = $self->run_name || 'unknown-run-name';
    return join '.', $run_name, $subset_name;
}

1;
