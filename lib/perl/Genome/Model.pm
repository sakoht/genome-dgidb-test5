package Genome::Model;

use strict;
use warnings;

use Genome;
use Regexp::Common;
use File::Path;
use YAML;

class Genome::Model {
    is => ['Genome::Notable','Genome::Searchable'],
    is_abstract => 1,
    subclassify_by => 'subclass_name',
    subclass_description_preprocessor => __PACKAGE__ . '::_preprocess_subclass_description',
    id_by => [
        genome_model_id => { is => 'Number', },
    ],
    attributes_have => [
        is_input    => { is => 'Boolean', is_optional => 1, },
        is_param    => { is => 'Boolean', is_optional => 1, },
        is_output   => { is => 'Boolean', is_optional => 1, },
        _profile_default_value => { is => 'Text', is_optional => 1, },
    ],
    has => [
        name => { is => 'Text' },
        subclass_name => { 
            is => 'VARCHAR2',is_mutable => 0, column_name => 'SUBCLASS_NAME',
            calculate_from => 'processing_profile_id',
            calculate => sub {
                my $processing_profile_id = shift;
                return unless $processing_profile_id;
                my $pp = Genome::ProcessingProfile->get($processing_profile_id);
                Carp::croak("Can't find Processing Profile with ID $processing_profile_id while resolving subclass for Model") unless $pp;
                return __PACKAGE__ . '::' . Genome::Utility::Text::string_to_camel_case($pp->type_name);
            },
        },
        subject_id => { is => 'Text' },
        subject_class_name => { is => 'Text', is_optional => 1, }, # FIXME This isn't really necessary anymore, should be refactored away
        subject => { 
            is => 'Genome::Subject',
            id_by => 'subject_id',
        },
        _sample_subject => {
            # returns the subject but only when it is a sample
            # allows samples to find their models more efficiently (update UR to automatically do reverse class disambiguation)
            is => 'Genome::Sample',
            is_optional => 1,
            id_by => 'subject_id',
        },
        subject_name => {
            via => 'subject',
            to => 'name',
        },
        subject_type => { 
            is => 'Text', 
            valid_values => ["species_name","sample_group","sample_name"], 
            calculate_from => 'subject_class_name',
            calculate => q|
                #This could potentially live someplace else like the previous giant hash
                my %types = (
                    'Genome::Sample' => 'sample_name',
                    'Genome::PopulationGroup' => 'sample_group',
                    'Genome::Individual' => 'sample_group',
                    'Genome::Taxon' => 'species_name',
                );
                return $types{$subject_class_name};
            |, 
        },

        processing_profile      => { is => 'Genome::ProcessingProfile', id_by => 'processing_profile_id' },
        processing_profile_id   => { is => 'Number', }, # this would be defined implicitly, but causes loading circularity with sub-classes
        processing_profile_name => { via => 'processing_profile', to => 'name' },
        type_name               => { via => 'processing_profile' },
    ],
    has_optional => [
        limit_inputs_id => {
            is => 'Text',
            column_name => 'LIMIT_INPUTS_TO_ID',
        },
        limit_inputs_rule => {
            is => 'UR::BoolExpr',
            id_by => 'limit_inputs_id',
        },
        user_name => { is => 'Text' },
        creation_date  => { is => 'Timestamp' },
        is_default => { 
            is => 'Boolean',
            doc => 'flag the model as the default system "answer" for its subject'
        },
        auto_assign_inst_data => { is => 'Boolean' },
        auto_build_alignments => { is => 'Boolean'}, # TODO: rename to auto_build
        build_requested => { is => 'Boolean'},
        keep_n_most_recent_builds => { 
            via => 'attributes', to => 'value', is_mutable => 1, 
            where => [ property_name => 'keep_n_most_recent_builds', entity_class_name => 'Genome::Model' ] 
        },
        _last_complete_build_id => { 
            is => 'Number', 
            column_name => 'last_complete_build_id', 
            doc => 'The last complete build id' ,
        },
        apipe_cron_status => {
            via => 'notes',
            to => 'body_text',
            where => [ header_text => 'apipe_cron_status' ],
            is_mutable => 0,
        },
    ],
    has_optional_many => [
        builds  => { 
            is => 'Genome::Model::Build', reverse_as => 'model',
            doc => 'versions of a model over time, with varying quantities of evidence' 
        },
        inputs => { 
            is => 'Genome::Model::Input', reverse_as => 'model',
            doc => 'links to data currently assigned to the model for processing' 
        },
        group_ids => { via => 'model_groups', to => 'id' },
        group_names => { via => 'model_groups', to => 'name' },
        # TODO: the new project will internally have generalized assignments of models and other things
        projects => { is => 'Genome::Project', via => 'project_parts', to => 'project', is_many => 1, is_mutable => 1, doc => 'Projects that include this model', },
        project_parts => { is => 'Genome::ProjectPart', reverse_as => 'entity', is_many => 1, is_mutable => 1, },
        project_names => { is => 'Text', via => 'projects', to => 'name', },
        # TODO: the new projects will suck in all of the model groups as a special case of a named project containing only models
        model_groups => { 
            is => 'Genome::ModelGroup', 
            via => 'model_bridges', 
            to => 'model_group',
            is_mutable => 1
        },
        model_bridges => { is => 'Genome::ModelGroupBridge', reverse_as => 'model' },
        # TODO: replace the internals of these with a specific case of model inputs
        from_model_links => { 
            is => 'Genome::Model::Link', reverse_as => 'to_model',
            doc => 'bridge table entries where this is the "to" model (used to retrieve models this model is "from"' 
        },
        from_models => { 
            is => 'Genome::Model', via => 'from_model_links', to => 'from_model',
            doc => 'Genome models that contribute "to" this model' 
        },
        to_model_links => { 
            is => 'Genome::Model::Link', reverse_as => 'from_model',
            doc => 'bridge entries where this is the "from" model(used to retrieve models models this model is "to")' 
        },
        to_models => { 
            is => 'Genome::Model', via => 'to_model_links', to => 'to_model',
            doc => 'Genome models this model contributes "to"' 
        },
        # TODO: ensure all misc attributes actually go into the db table so we don't need this 
        attributes => { 
            is => 'Genome::MiscAttribute', 
            reverse_as => '_model', 
            where => [ entity_class_name => 'Genome::Model' ] 
        },
        # TODO: these go into a model subclass for models which apply directly to sequencer data
        sequencing_platform         => { via => 'processing_profile' },
        instrument_data_class_name  => { is => 'Text',
                                        calculate_from => 'sequencing_platform',
                                        calculate => q| 'Genome::InstrumentData::' . ucfirst($sequencing_platform) |,
                                        doc => 'the class of instrument data assignable to this model' },
        instrument_data_inputs => {
            is => 'Genome::Model::Input',
            reverse_as => 'model',
            where => [ name => 'instrument_data' ],
        },
        instrument_data => {
            is => 'Genome::InstrumentData',
            via => 'inputs',
            to => 'value', 
            is_mutable => 1, 
            where => [ name => 'instrument_data' ],
            doc => 'Instrument data currently assigned to the model.' 
        },
        instrument_data_ids => { via => 'instrument_data', to => 'id' },
    ],    
    has_optional_deprecated => [
        # this is all junk but things really use them right now 
        events                  => { is => 'Genome::Model::Event', reverse_as => 'model', is_many => 1,
            doc => 'all events which have occurred for this model' },
        reports                 => { via => 'last_succeeded_build' },
        reports_directory       => { via => 'last_succeeded_build' },
        
        # these go on refalign models
        region_of_interest_set_name => { 
            is => 'Text',
            is_many => 1, 
            is_mutable => 1,
            via => 'inputs', 
            to => 'value_id',
            where => [ name => 'region_of_interest_set_name', value_class_name => 'UR::Value' ], 
        },
        merge_roi_set => {
            is_mutable => 1,
            via => 'inputs', 
            to => 'value_id',
            where => [ name => 'merge_roi_set', value_class_name => 'UR::Value' ], 
        },
        short_roi_names => {
            is_mutable => 1,
            via => 'inputs', 
            to => 'value_id',
            where => [ name => 'short_roi_names', value_class_name => 'UR::Value' ], 
        },
    ],
    has_optional_calculated => [
        individual_common_name => {
            is => 'Text',
            calculate_from => 'subject',
            calculate => q{
                if ($subject->class eq 'Genome::Individual') {
                    return $subject->common_name();
                } elsif($subject->class eq 'Genome::Sample') {
                    return $subject->patient_common_name();
                } else {
                    return undef;
                }
            },
        },
        sample_names => {
            is => 'Array',
            calculate => q{
                my @s = $self->get_all_possible_samples();
                return sort map {$_->name()} @s;
            },
        },
        sample_names_for_view => {
            is => 'Array',
            calculate => q{
                my @s = $self->get_samples_for_view();
                return sort map {$_->name()} @s;
            },
        },
    ],
    has_deprecated_optional => [
        # TODO: add an is_in_latest_build flag to the input and make these a parameter
        # clean up tracking on last_complete_build and make these delegate, or throw them away
        last_complete_build_directory    => { calculate => q|$b = $self->last_complete_build; return unless $b; return $b->data_directory| },
        last_succeeded_build_directory   => { calculate => q|$b = $self->last_succeeded_build; return unless $b; return $b->data_directory| },

        # used in a few odd places 
        build_statuses                  => { via => 'builds', to => 'master_event_status', is_many => 1 },
        build_ids                       => { via => 'builds', to => 'id', is_many => 1 },
   
        # this should match the subject_name for models with samples as subjects
        # sadly, existing capture code uses this method
        sample_name                     => { is => 'Text', doc => 'deprecated column with explicit sample_name tracking' },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
    table_name => 'GENOME_MODEL',
    doc => 'a versioned data model describing one the sequence and features of a genome' 
};

sub __display_name__ {
    my $self = shift;
    return $self->name . ' (' . $self->id . ')';
}

my $depth = 0;
sub __extend_namespace__ {
    # auto generate sub-classes for any valid processing profile
    my ($self,$ext) = @_;

    my $meta = $self->SUPER::__extend_namespace__($ext);
    if ($meta) {
        return $meta;
    }

    $depth++;
    if ($depth>1) {
        $depth--;
        return;
    }

    my $pp_subclass_name = 'Genome::ProcessingProfile::' . $ext;
    my $pp_subclass_meta = UR::Object::Type->get($pp_subclass_name);
    if ($pp_subclass_meta and $pp_subclass_name->isa('Genome::ProcessingProfile')) {
        my @pp_delegated_properties = map {
            $_ => { via => 'processing_profile' }
        } $pp_subclass_name->params_for_class;

        my $model_subclass_name = 'Genome::Model::' . $ext;
        my $model_subclass_meta = UR::Object::Type->define(
            class_name => $model_subclass_name,
            is => 'Genome::Model',
            has => \@pp_delegated_properties
        );
        die "Error defining $model_subclass_name for $pp_subclass_name!" unless $model_subclass_meta;
        $depth--;
        return $model_subclass_meta;
    }
    $depth--;
    return;
}

sub create {
    my $class = shift;

    if ($class eq __PACKAGE__ or $class->__meta__->is_abstract) {
        # this class is abstract, and the super-class re-calls the constructor from the correct subclass
        return $class->SUPER::create(@_);
    }

    my $params;
    my $entered_subject_name; #So the user gets what they expect, use this when coming up with the default model name

    #Create gets called twice... Only set things up the first time
    #The second time we get the UR::BoolExpr handed to us.
    if(ref $_[0]) {
        $params = $class->define_boolexpr(@_);
    } 
    else {
        my %input_params = @_;

        if(exists $input_params{subject_name} or exists $input_params{subject_type}) {
            $entered_subject_name = delete $input_params{subject_name};
            my $entered_subject_type = delete $input_params{subject_type};

            if(exists $input_params{subject_id} and defined $input_params{subject_id}
                and exists $input_params{subject_class_name} and defined $input_params{subject_class_name}) {
                #They already gave us a subject; we'll test if it's good in _verify_subject below.
                #Just ignore the other parameters--
            } else {
                my $subject = $class->_resolve_subject_from_name_and_type($entered_subject_name, $entered_subject_type)
                    or return;

                $input_params{subject_id} = $subject->id;
                $input_params{subject_class_name} = $subject->class;
            }
        }

        $params = $class->define_boolexpr(%input_params);
    }

    # Processing profile - gotta validate here or SUPER::create will fail silently
    my $processing_profile_id = $params->value_for('processing_profile_id');
    $class->_validate_processing_profile_id($processing_profile_id)
        or Carp::confess();

    my $self = $class->SUPER::create($params) or return;

    # do this until we drop the subject_class_name column
    my $subject = $self->subject();

    if (not $subject and $self->can("_resolve_subject")) {
        $subject = $self->_resolve_subject();
    }

    if ($subject) {
        $self->subject_class_name(ref($subject));
        $self->subject_id($subject->id);
    }

    # Make sure the subject we got is really an object
    unless ( $self->_verify_subject ) {
        $self->SUPER::delete;
        return;
    }

    # user/creation
    unless ($self->user_name) {
        my $user = getpwuid($<);
        $self->user_name($user);
    }

    unless ($self->creation_date) {
        $self->creation_date(UR::Time->now);
    }

    # Set model name to default is none given
    if ( not defined $self->name ) {
        my $default_name = $self->default_model_name;
        if ( not defined $default_name ) {
            $self->error_message("No model name given and cannot get a default name from $class");
            $self->SUPER::delete;
            return;
        }
        $self->name($default_name);
    }

    # Check that this model doen't already exist.  If other models with the same name
    #  and type name exist, this method lists them, errors and deletes this model.
    #  Checking after subject verification to catch that error first.
    $self->_verify_no_other_models_with_same_name_and_type_name_exist
        or return;

    my $processing_profile= $self->processing_profile;
    unless ($processing_profile->_initialize_model($self)) {
        $self->error_message("The processing profile failed to initialize the new model:"
            . $processing_profile->error_message);
        $self->delete;
        return;
    }

    # If build requested was set as part of model creation, it didn't use the mutator method that's been
    # overridden. Re-set it here so the require actions take place
    # TODO Rather than directly creating a model with build_requested set, should probably just start a build
    if ($self->build_requested) {
        $self->build_requested($self->build_requested, 'model created with build requested set');
    }

    return $self;
}

sub _validate_processing_profile_id {
    my ($class, $pp_id) = @_;
    unless ( $pp_id ) {
        $class->error_message("No processing profile id given");
        return;
    }
    unless ( $pp_id =~ m/^$RE{num}{int}$/) {
        $class->error_message("Processing profile id is not an integer");
        return;
    }
    unless ( Genome::ProcessingProfile->get(id => $pp_id) ) {
        $class->error_message("Can't get processing profile for id ($pp_id)");
        return;
    }
    return 1;
}

sub _verify_no_other_models_with_same_name_and_type_name_exist {
    # Checks that this model doen't already exist.  If other models with the same name
    #  and type name exist, this method lists them, errors and deletes this model.
    #  Should only be called from create.
    my $self = shift;

    my @models = Genome::Model->get(
        id => {
            operator => '!=',
            value => $self->id,
        },
        name => $self->name,
        type_name => $self->type_name
    );

    return 1 unless @models; # ok

    my $message = "\n";
    for my $model ( @models ) {
        $message .= sprintf(
            "Name: %s\nSubject Name: %s\nId: %s\nProcessing Profile Id: %s\nType Name: %s\n\n",
            $model->name,
            $model->subject_name,
            $model->id,
            $model->processing_profile_id,
            $model->type_name,

        );
    }
    $message .= sprintf(
        'Found the above %s with the same name and type name.  Please select a new name.',
        Lingua::EN::Inflect::PL('model', scalar(@models)),
    );
    $self->error_message($message);
    $self->delete;

    return;
}

# TODO This method should return a generic default model name and be overridden in subclasses.
sub default_model_name {
    my ($self, %params) = @_;

    my $auto_increment = delete $params{auto_increment};
    $auto_increment = 1 unless defined $auto_increment;

    my $name_template = ($self->subject_name).'.';
    $name_template .= 'prod-' if ($self->user_name eq 'apipe-builder' || $params{prod});

    my $type_name = $self->processing_profile->type_name;
    my %short_names = (
        'genotype microarray' => 'microarray',
        'reference alignment' => 'refalign',
        'de novo assembly' => 'denovo',
        'metagenoic composition 16s' => 'mc16s',
    );
    $name_template .= ( exists $short_names{$type_name} )
    ? $short_names{$type_name}
    : join('_', split(/\s+/, $type_name));

    $name_template .= '%s%s';

    my @parts;
    push @parts, 'capture', $params{capture_target} if defined $params{capture_target};
    push @parts, $params{roi} if defined $params{roi};
    my @additional_parts = eval{ $self->_additional_parts_for_default_name(%params); };
    if ( $@ ) {
        $self->error_message("Failed to get addtional default name parts: $@");
        return;
    }
    push @parts, @additional_parts if @additional_parts;
    $name_template .= '.'.join('.', @parts) if @parts;

    my $name = sprintf($name_template, '', '');
    my $cnt = 0;
    while ( $auto_increment && Genome::Model->get(name => $name) ) {
        $name = sprintf($name_template, '-', ++$cnt);
    }

    return $name;
}

sub _additional_parts_for_default_name { return; }

# TODO This can likely be simplified once all subjects are a subclass of Genome::Subject
#If a user defines a model with a name (and possibly type), we need to find/make sure there's an
#appropriate subject to use based upon that name/type.
sub _resolve_subject_from_name_and_type {
    my $class = shift;
    my $subject_name = shift;
    my $subject_type = shift;

    if (not defined $subject_name) {
        $class->error_message("bad data--missing subject_name!");
        return;
    }

    my $try_all_types = 0;
    if (not defined $subject_type) {
        #If they didn't give a subject type, we'll keep trying subjects until we find something that sticks.
        $try_all_types = 1;
    }

    my @subjects = ();

    if($try_all_types or $subject_type eq 'sample_name') {
        my $subject = Genome::Sample->get(name => $subject_name);
        return $subject if $subject; #sample_name is the favoured default.  If we get one, use it.
    }
    if ($try_all_types or $subject_type eq 'species_name') {
        push @subjects, Genome::Taxon->get(name => $subject_name);
    }
    if ($try_all_types or $subject_type eq 'library_name') {
        push @subjects, Genome::Library->get(name => $subject_name);
    }
    if ($try_all_types or $subject_type eq 'genomic_dna') {
        push @subjects, Genome::Sample->get(extraction_label => $subject_name, extraction_type => 'genomic dna');
    }

    #This case will only be entered if the user asked specifically for a sample_group
    if ($subject_type and $subject_type eq 'sample_group') {
        push @subjects,
            Genome::Individual->get(name => $subject_name),
            Genome::ModelGroup->get(name => $subject_name),
            Genome::PopulationGroup->get(name => $subject_name);
    }

    if(scalar @subjects == 1) {
        return $subjects[0];
    } elsif (scalar @subjects) {
        my $null = '<NULL>';
        $class->error_message('Multiple matches for ' . join(', ',
            'subject_name: ' . ($subject_name || $null),
            'subject_type: ' . ($subject_type || $null),
        ) . '. Please specify a subject_type or use subject_id/subject_class_name instead.'
        );
        $class->error_message('Possible subjects named "' . $subject_name . '": ' . join(', ',
            map($_->class . ' #' . $_->id, @subjects)
        ));
    } else {
        #If we get here, nothing matched.
        my $null = '<NULL>';
        $class->error_message('Unable to determine a subject given ' . join(', ',
            'subject_name: ' . ($subject_name || $null),
            'subject_type: ' . ($subject_type || $null),
        ));
        return;
    }
}

# TODO Can be removed when all subjects are Genome::Subject
sub _verify_subject {
    my $self = shift;
    unless ($self->subject) {
        $self->error_message("Could not retrieve subject object for model " . $self->__display_name__ 
            . " with ID " . $self->subject_id . " and class " . $self->subject_class_name);
        return 0;
    }

    unless ($self->subject->isa('Genome::Subject')) {
        $self->error_message("Subject of model  " . $self->__display_name__ . 
            " is not a Genome::Subject, it's a " . $self->subject->class);
        return 0;
    }
    return 1;
}

sub get_samples_for_view {

    my ($self) = shift;

    my $subject = $self->subject();
    my @samples;

    if ($self->subject_class_name eq 'Genome::Sample') {
       @samples = ($subject);
    } elsif ( $self->subject_class_name eq 'Genome::Individual') {
       @samples = $subject->samples();
    }
    return @samples;
}

sub get_all_possible_samples {
    my $self = shift;

    my @samples;
    if ( $self->subject_class_name eq 'Genome::Taxon' ) {
        my $taxon = Genome::Taxon->get(name => $self->subject_name);
        @samples = $taxon->samples();

        #data tracking is incomplete, so sometimes these need to be looked up via the sources
        my @sources = ($taxon->individuals, $taxon->population_groups);
        push @samples,
            map($_->samples, @sources);
    } elsif ($self->subject_class_name eq 'Genome::Sample'){
        @samples = ( $self->subject );
    } elsif ($self->subject_class_name eq 'Genome::Individual') {
        @samples = $self->subject->samples();
    #} elsif () {
        #TODO Possibly fill in for possibly Genome::PopulationGroup and possibly others (possibly)
    } else {
        @samples = ();
    }

    return @samples;
}

#< Instrument Data >#
sub input_for_instrument_data_id {
    my ($self, $id) = @_;
    return unless $id;
    for my $input ($self->instrument_data_inputs) {
        return $input if $input->value_id eq $id;
    }
    return;
}

sub input_for_instrument_data {
    my ($self, $instrument_data) = @_;
    return unless $instrument_data;
    return $self->input_for_instrument_data_id($instrument_data->id);
}

sub has_instrument_data {
    my ($self, $instrument_data) = @_;
    my $input;
    if (ref $instrument_data) {
        $input = $self->input_for_instrument_data($instrument_data);
    }
    else {
        $input = $self->input_for_instrument_data_id($instrument_data);
    }
    return $input;
}

sub unbuilt_instrument_data {
    my $self = shift;
    my %model_data;
    map { $model_data{$_} = 1 } $self->instrument_data_ids;
    my @unbuilt_data;
    for my $build ($self->builds) {
        for my $build_data ($build->instrument_data_ids) {
            my $model_data = delete $model_data{$build_data};
            next if defined $model_data;
            push @unbuilt_data, $build_data;
        }
    }
    push @unbuilt_data, keys %model_data;
    return @unbuilt_data;
}

sub compatible_instrument_data {
    my $self = shift;
    my %params;

    my $subject_type_class;
    if (my @samples = $self->get_all_possible_samples)  {
        my @sample_ids = map($_->id, @samples);
        %params = (
                   sample_id => \@sample_ids,
               );
        $params{sequencing_platform} = $self->sequencing_platform if $self->sequencing_platform;
    } else {
        %params = (
                   $self->subject_type => $self->subject_name,
               );
        $subject_type_class = $self->instrument_data_class_name;
    }
    unless ($subject_type_class) {
        $subject_type_class = 'Genome::InstrumentData';
    }
    my @compatible_instrument_data = $subject_type_class->get(%params);

    if($params{sequencing_platform} and $params{sequencing_platform} eq 'solexa') {
        # FASTQs with 0 reads crash in alignment.  Don't assign them. -??
        # TODO: move this into the assign logic, not here. -ss
        my @filtered_compatible_instrument_data;
        for my $idata (@compatible_instrument_data) {
            if (defined($idata->total_bases_read)&&($idata->total_bases_read == 0)) {
                $self->warning_message(sprintf("ignoring %s because it has zero bases read",$idata->__display_name__));
                next;
            }
            else {
                push @filtered_compatible_instrument_data, $idata;
            }
        }
        @compatible_instrument_data = @filtered_compatible_instrument_data;
    }

    return @compatible_instrument_data;
}
sub assigned_instrument_data { return $_[0]->instrument_data; }
sub available_instrument_data { return unassigned_instrument_data(@_); }
sub unassigned_instrument_data {
    my $self = shift;

    my @compatible_instrument_data = $self->compatible_instrument_data;
    my @assigned = $self->instrument_data;
    return @compatible_instrument_data unless @assigned;

    my %assigned_instrument_data_ids = map { $_->id => 1 } @assigned;
    return grep { not $assigned_instrument_data_ids{$_->id} } @compatible_instrument_data;
}

#< Completed (also Suceeded) Builds >#
sub succeeded_builds { return $_[0]->completed_builds; }
sub completed_builds {
    my $self = shift;

    my @completed_builds;
    for my $build ( $self->builds('-hint' => ['the_master_event']) ) {
        my $build_status = $build->status;
        next unless defined $build_status and $build_status eq 'Succeeded';
        next unless defined $build->date_completed; # error?
        push @completed_builds, $build;
    }

    return sort { $a->id <=> $b->id } @completed_builds;
}

sub latest_build {
    my $self = shift;
    my @builds = $self->builds(@_);
    return $builds[-1] if @builds;
    return;
}

sub latest_build_id {
    my $self = shift;
    my $build = $self->latest_build(@_);
    unless ($build) { return; }
    return $build->id;
}

sub status_with_build {
    my $self = shift;

    my ($status, $build);
    if ($self->build_requested) {
        $status = 'Build Requested';
    } elsif ($self->build_needed) {
        $status = 'Build Needed';
    } else {
        $build = $self->current_build;
        $status = $build->status;
    }

    return ($status, $build);
}

sub status {
    my $self = shift;
    my ($status) = $self->status_with_build;
    return $status;
}

sub latest_build_status {
    my $self = shift;
    my $build = $self->latest_build(@_);
    unless ($build) { return; }
    return $build->status;
}

sub last_succeeded_build { return $_[0]->resolve_last_complete_build; }
sub last_complete_build { return $_[0]->resolve_last_complete_build; }
sub resolve_last_complete_build {
    my $self = shift;
    my @completed_builds = $self->completed_builds;
    return unless @completed_builds;
    my $last = pop @completed_builds;
    unless ( defined $self->_last_complete_build_id
            and $self->_last_complete_build_id == $last->id ) {
        $self->_last_complete_build_id( $last->id );
    }
    return $last;
}

sub last_succeeded_build_id { return $_[0]->last_complete_build_id; }
sub last_complete_build_id {
    my $self = shift;
    my $last_complete_build = $self->last_complete_build;
    return unless $last_complete_build;
    return $last_complete_build->id;
}

sub builds_with_status {
    my ($self, $status) = @_;
    my @builds = $self->builds;
    unless (scalar(@builds)) {
        return;
    }
    my @builds_with_a_status = grep { $_->status } @builds;
    my @builds_with_requested_status = grep {$_->status eq $status} @builds_with_a_status;
    my @builds_wo_date = grep { !$_->date_scheduled } @builds_with_requested_status;
    if (scalar(@builds_wo_date)) {
        my $error_message = 'Found '. scalar(@builds_wo_date) ." $status builds without date scheduled.\n";
        for (@builds_wo_date) {
            $error_message .= "\t". $_->desc ."\n";
        }
        die($error_message);
    }
    my @sorted_builds_with_requested_status = sort {$a->date_scheduled cmp $b->date_scheduled} @builds_with_requested_status;
    return @sorted_builds_with_requested_status;
}

sub abandoned_builds {
    my $self = shift;
    my @abandoned_builds = $self->builds_with_status('Abandoned');
    return @abandoned_builds;
}
sub failed_builds {
    my $self = shift;
    my @failed_builds = $self->builds_with_status('Failed');
    return @failed_builds;
}
sub running_builds {
    my $self = shift;
    my @running_builds = $self->builds_with_status('Running');
    return @running_builds;
}
sub scheduled_builds {
    my $self = shift;
    my @scheduled_builds = $self->builds_with_status('Scheduled');
    return @scheduled_builds;
}

sub current_running_build {
    my $self = shift;
    my @running_builds = $self->running_builds;
    my $current_running_build = pop(@running_builds);
    return $current_running_build;
}

sub current_running_build_id {
    my $self = shift;
    my $current_running_build = $self->current_running_build;
    unless ($current_running_build) {
        return;
    }
    return $current_running_build->id;
}

sub latest_build_directory {
    my $self = shift;
    my $current_running_build = $self->current_running_build;
    if (defined $current_running_build) {
        return $current_running_build->data_directory;
    }
    my $last_complete_build = $self->last_complete_build;
    if (defined $last_complete_build) {
        return $last_complete_build->data_directory;
    } else {
       return;
    }
}

# This is called by both of the above.
sub _resolve_subclass_name_for_type_name {
    my ($class,$type_name) = @_;
    my @type_parts = split(' ',$type_name);

    my @sub_parts = map { ucfirst } @type_parts;
    my $subclass = join('',@sub_parts);

    my $class_name = join('::', 'Genome::Model' , $subclass);
    return $class_name;
}

sub _resolve_type_name_for_subclass_name {
    my ($class,$subclass_name) = @_;
    my ($ext) = ($subclass_name =~ /Genome::Model::(.*)/);
    return unless ($ext);
    my @words = $ext =~ /[a-z]+|[A-Z](?:[A-Z]+|[a-z]*)(?=$|[A-Z])/g;
    my $type_name = lc(join(" ", @words));
    return $type_name;
}

# TODO: please rename this -ss
sub get_all_objects {
    my $self = shift;
    my $sorter = sub { # not sure why we sort, but I put it in a anon sub for convenience
        return unless @_;
        if ( $_[0]->id =~ /^\-/) {
            return sort {$b->id cmp $a->id} @_;
        }
        else {
            return sort {$a->id cmp $b->id} @_;
        }
    };

    return map { $sorter->( $self->$_ ) } (qw{ inputs builds to_model_links from_model_links });
}

sub yaml_string {
    my $self = shift;
    my $string = YAML::Dump($self);
    my @objects = $self->get_all_objects;
    for my $object (@objects) {
        $string .= $object->yaml_string;
    }
    return $string;
}

# TODO Will be removed when model links are phased out
# TODO please rename this -ss
sub add_to_model{
    my $self = shift;
    my (%params) = @_;
    my $model = delete $params{to_model};
    my $role = delete $params{role};
    $role||='member';

    $self->error_message("no to_model provided!") and die unless $model;
    my $from_id = $self->id;
    my $to_id = $model->id;
    unless( $to_id and $from_id){
        $self->error_message ( "no value for this model(from_model) id: <$from_id> or to_model id: <$to_id>");
        die;
    }
    my $reverse_bridge = Genome::Model::Link->get(from_model_id => $to_id, to_model_id => $from_id);
    if ($reverse_bridge){
        my $string =  "A model link already exists for these two models, and in the opposite direction than you specified:\n";
        $string .= "to_model: ".$reverse_bridge->to_model." (this model)\n";
        $string .= "from_model: ".$reverse_bridge->from_model." (the model you are trying to set as a 'to' model for this one)\n";
        $string .= "role: ".$reverse_bridge->role;
        $self->error_message($string);
        die;
    }
    my $bridge = Genome::Model::Link->get(from_model_id => $from_id, to_model_id => $to_id);
    if ($bridge){
        my $string =  "A model link already exists for these two models:\n";
        $string .= "to_model: ".$bridge->to_model." (the model you are trying to set as a 'to' model for this one)\n";
        $string .= "from_model: ".$bridge->from_model." (this model)\n";
        $string .= "role: ".$bridge->role;
        $self->error_message($string);
        die;
    }
    $bridge = Genome::Model::Link->create(from_model_id => $from_id, to_model_id => $to_id, role => $role);
    return $bridge;
}

# TODO Will be removed when model links are phased out
# TODO please rename this -ss
sub add_from_model{
    my $self = shift;
    my (%params) = @_;
    my $model = delete $params{from_model};
    my $role = delete $params{role};
    $role||='member';

    $self->error_message("no from_model provided!") and die unless $model;
    my $to_id = $self->id;
    my $from_id = $model->id;
    unless( $to_id and $from_id){
        $self->error_message ( "no value for this model(to_model) id: <$to_id> or from_model id: <$from_id>");
        die;
    }
    my $reverse_bridge = Genome::Model::Link->get(from_model_id => $to_id, to_model_id => $from_id);
    if ($reverse_bridge){
        my $string =  "A model link already exists for these two models, and in the opposite direction than you specified:\n";
        $string .= "to_model: ".$reverse_bridge->to_model." (the model you are trying to set as a 'from' model for this one)\n";
        $string .= "from_model: ".$reverse_bridge->from_model." (this model)\n";
        $string .= "role: ".$reverse_bridge->role;
        $self->error_message($string);
        die;
    }
    my $bridge = Genome::Model::Link->get(from_model_id => $from_id, to_model_id => $to_id);
    if ($bridge){
        my $string =  "A model link already exists for these two models:\n";
        $string .= "to_model: ".$bridge->to_model." (this model)\n";
        $string .= "from_model: ".$bridge->from_model." (the model you are trying to set as a 'from' model for this one)\n";
        $string .= "role: ".$bridge->role;
        $self->error_message($string);
        die;
    }
    $bridge = Genome::Model::Link->create(from_model_id => $from_id, to_model_id => $to_id, role => $role);
    return $bridge;
}

sub notify_input_build_success {
    my $self = shift;
    my $succeeded_build = shift;

    if($self->auto_build_alignments) {
        my @from_models = $self->from_models;
        my @last_complete_builds = map($_->last_complete_build, @from_models);

        #all input models have a succeeded build
        if(scalar @from_models eq scalar @last_complete_builds) {
            $self->build_requested(1, 'all input models are ready');
        }
    }

    return 1;
}

sub create_rule_limiting_instrument_data {
    my ($self, @instrument_data) = @_;
    @instrument_data = $self->instrument_data unless @instrument_data;
    return unless @instrument_data;

    # Find the smallest scale domain object that encompasses all the instrument data
    # and create a boolean expression for it.
    for my $accessor (qw/ library_id sample_id sample_source_id taxon_id /) {
        my @ids = map { $_->$accessor } @instrument_data;
        next unless @ids;
        next if grep { $_ ne $ids[0] } @ids;

        my $rule = $instrument_data[0]->define_boolexpr($accessor => $ids[0]);
        return $rule;
    }

    return;
}
    
sub build_requested {
    my ($self, $value, $reason) = @_; 
    # Writing the if like this allows someone to do build_requested(undef)
    if (@_ > 1) {
        my ($calling_package, $calling_subroutine) = (caller(1))[0,3];
        my $default_reason = 'no reason given';
        $default_reason .= ' called by ' . $calling_package . '::' . $calling_subroutine if $calling_package;
        $self->add_note(
            header_text => $value ? 'build_requested' : 'build_unrequested',
            body_text => defined $reason ? $reason : $default_reason,
        );
        return $self->__build_requested($value);
    }

    return $self->__build_requested;
}

sub latest_build_request_note {
    my $self = shift;
    my @notes = sort { $b->entry_date cmp $a->entry_date } grep { $_->header_text eq 'build_requested' } $self->notes;
    return unless @notes;
    return $notes[0];
}
    
sub time_of_last_build_request {
    my $self = shift;
    my $note = $self->latest_build_request_note;
    return unless $note;
    return $note->entry_date;
}

sub params_from_param_strings {
    my ($class, @param_strings) = @_;

    Carp::confess('No param strings to convert to params') if not @param_strings;

    my %params;
    my $meta = $class->__meta__;
    for my $param_string ( @param_strings ) {
        my ($key, $value) = split('=', $param_string, 2);
        my $property = $meta->property_meta_for_name($key);
        if ( not $property ) {
            $class->error_message("Failed to find model property: $key");
            return;
        }

        if ( my ($unallowed) = grep { $property->$_ } (qw/ is_calculated is_constant is_transient /) ){
            $class->error_message("Property ($key) cannot be given on the command line because it is '$unallowed'");
            return;
        }

        if ( not defined $value or $value eq '' ) {
            $params{$key} = undef;
            next;
        }

        my @values = $value;
        my $data_type = $property->data_type;
        if ( not grep { $data_type =~ /^$_$/i } (qw/ boolean integer number string text ur::value /) ) { # hacky...if u kno a better way...
            my $filter = ( $value =~ /^$RE{num}{int}$/ ) ? 'id='.$value : $value;
            my $data_type = $property->data_type;
            my $bx = eval { UR::BoolExpr->resolve_for_string($data_type, $filter); };
            if ( not $bx ) {
                $class->error_message("Failed to create expression for $key ($data_type) from '$value'");
                return;
            }
            @values = $data_type->get($bx);
            if ( not @values ) {
                $class->error_message("Failed to get $key ($data_type) for $value");
                return;
            }
        }

        if ( $property->is_many ) {
            push @{$params{$key}}, @values;
        }
        elsif ( @values > 1 or exists $params{$key} ) {
            $class->error_message(
                "Singular property ($key) cannot have more than one value (".join(', ', grep { defined } (@values, $params{$key})).')'
            );
            return;
        }
        else {
            $params{$key} = $values[0];
        }
    }

    return %params;
}

sub property_names_for_copy {
    my $class = shift;

    my $meta = eval{ $class->__meta__; };
    if ( not $meta ) {
        $class->error_message('Failed to get class meta for '.$class);
        return;
    }

    my @base_properties = (qw/
        auto_assign_inst_data auto_build_alignments processing_profile subject 
        /);

    my @input_properties = map { 
        $_->property_name
    } grep { 
        defined $_->via and $_->via eq 'inputs'
    } $meta->property_metas;

    return sort { $a cmp $b } ( @base_properties, @input_properties );
}

sub real_input_properties {
    my $self = shift;

    my $meta = $self->__meta__;
    my @properties;
    for my $input_property ( sort { $a->property_name cmp $b->property_name } grep { $_->{is_input} or ( $_->via and $_->via eq 'inputs' ) } $meta->property_metas ) {
        my $property_name = $input_property->property_name;
        my %property = (
            name => $property_name,
            is_optional => $input_property->is_optional,
            is_many => $input_property->is_many,
            data_type => $input_property->data_type,
        );

        if($input_property->{is_input}) {
            $property{input_name} = $property_name;
        } else {
            my $where = $input_property->where;
            my %where = @$where;
            $property{input_name} = $where{name};
        }

        if ( $input_property->is_many ) {
            $property{add_method} = 'add_'.$input_property->singular_name,
            $property{remove_method} = 'remove_'.$input_property->singular_name,
        }
        push @properties, \%property;
        next if not $property_name =~ s/_id$//;
        my $object_property = $meta->property_meta_for_name($property_name);
        next if not $object_property;
        $property{name} = $object_property->property_name;
        $property{data_type} = $object_property->data_type;
    }

    return @properties;
}

sub copy {
    my ($self, %overrides) = @_;

    # standard properties
    my %params = ( subclass_name => $self->subclass_name );
    $params{name} = delete $overrides{name} if defined $overrides{name};
    my @standard_properties = (qw/ subject processing_profile auto_assign_inst_data auto_build_alignments /);
    for my $name ( @standard_properties ) {
        if ( defined $overrides{$name} ) { # override
            $params{$name} = delete $overrides{$name};
        }
        elsif ( exists $overrides{$name} ) { # rm undef
            delete $overrides{$name};
        }
        else {
            $params{$name} = $self->$name;
        }
    }

    # input properties
    for my $property ( $self->real_input_properties ) {
        my $name = $property->{name};
        if ( defined $overrides{$name} ) { # override
            my $ref = ref $overrides{$name};
            if ( $ref and $ref eq  'ARRAY' and not $property->{is_many} ) {
                $self->error_message('Cannot override singular input with multiple values: '.Data::Dumper::Dumper({$name => $overrides{$name}}));
                return;
            }
            $params{$name} = delete $overrides{$name};
        }
        elsif ( exists $overrides{$name} ) { # rm undef
            delete $overrides{$name};
        }
        else {
            if ( $property->{is_many} ) {
                $params{$name} = [ $self->$name ];
            }
            else {
                if( defined $self->$name ) {
                    $params{$name} = $self->$name;
                }
            }
        }
    }

    # make we covered all overrides
    if ( %overrides ) {
        $self->error_message('Unrecognized overrides sent to model copy: '.Data::Dumper::Dumper(\%overrides));
        return;
    }

    $params{subject_class_name} = $params{subject}->class; # set here in case subject is overridden

    my $copy = eval{ $self->class->create(%params) };
    if ( not $copy ) {
        $self->error_message('Failed to copy model: '.$@);
        return;
    }

    return $copy;
}

sub delete {
    my $self = shift;
    my @build_directories;

    for my $model_group ($self->model_groups) {
        $self->status_message("Removing model " . $self->__display_name__ . " from model group " . $model_group->__display_name__ . ".");
        $model_group->unassign_models($self);
    }
    die $self->error_message("Failed to remove model from all model groups.") if ($self->model_groups);

    # This may not be the way things are working but here is the order of operations for removing db events
    # 1.) Set model last_complete_build_id and current_running_build_id to null
    # 2.) Remove all genome_model_build entries
    # 3.) Remove all genome_model_event entries
    # 4.) Remove the genome_model entry

    my @objects = $self->get_all_objects;
    for my $object (@objects) {
        my $status = $object->delete;
        unless ($status) {
            $self->error_message('Failed to remove object '. $object->class .' '. $object->id);
            die $self->error_message();
        }
    }
    # Get the remaining events like create and assign instrument data
    for my $event ($self->events) {
        unless ($event->delete) {
            $self->error_message('Failed to remove event '. $event->class .' '. $event->id);
            die $self->error_message();
        }
    }

    return $self->SUPER::delete;
}

sub dependent_properties {
    my ($self, $property_name) = @_;
    return;
}

# Updates the model as necessary prior to starting a build. Useful for ensuring that the build is incorporating
# all of the latest information. Override in subclasses for custom behavior.
sub check_for_updates {
    return 1;
}

sub set_apipe_cron_status {
    my $self = shift;
    my $body_text = shift;

    my @header = (header_text => 'apipe_cron_status');

    my $note = $self->notes(@header);
    $note->delete if ($note);

    $self->add_note(@header, body_text => $body_text);
}

sub current_build {
    my $self = shift;
    my @builds = $self->builds('status not like' => 'Abandoned');
    for my $build (reverse @builds) {
        if ($build->is_current) {
            return $build;
        }
    }
    return;
}

sub build_needed {
    return not shift->current_build;
}

#To be overridden by subclasses--if there is a case where the build and model are expected to differ
sub _input_differences_are_ok {
    my $self = shift;
    my @inputs_not_found = @{shift()};
    my @build_inputs_not_found = @{shift()};

    return; #by default all differences are not ok
}

#To be overridden by subclasses--this check is performed early so validating this may save other work
sub _input_counts_are_ok {
    my $self = shift;
    my $input_count = shift;
    my $build_input_count = shift;

    return ($input_count == $build_input_count);
}

sub duplicates {
    my $self    = shift || die;
    my $pp      = $self->processing_profile || die;
    my $class   = $self->class || die;
    my $subject = $self->subject || die;
    my @inputs  = $self->inputs;

    # duplicates would have the same subject, processing profile, and inputs
    # but we have to compare the values of the inputs not the inputs themselves
    my @duplicates;
    my @other_models;
    if (@_) {
        @other_models = grep { $_->subject_id eq $subject->id} @_;
    } else {
        @other_models = $class->get(subject_id => $subject->id, processing_profile_id => $pp->id);
    }

    my $instrument_data_ids = join(",", sort $self->instrument_data);
    for my $other_model (@other_models) {
        my $other_instrument_data_ids = join(",", sort $other_model->instrument_data);
        next unless $instrument_data_ids eq $other_instrument_data_ids;

        my @other_inputs = $other_model->inputs;
        next if (@other_inputs != @inputs); # mainly to catch case where one has inputs but other does not

        my $matched_inputs = 0;
        for my $input (@inputs) {
            my @other_duplicate_inputs = $other_model->inputs(name => $input->name, value_id => $input->value_id, value_class_name => $input->value_class_name);
            $matched_inputs++ if (@other_duplicate_inputs);
        }
        push @duplicates, $other_model if (@inputs == $matched_inputs);
    }

    @duplicates = grep { $_->id ne $self->id } @duplicates;

    return @duplicates;
}

sub is_used_as_model_or_build_input {
    # Both models and builds have this method and as such it is currently duplicated.
    # We don't seem to have any place to put things that are common between Models and Builds.
    my $self = shift;

    my @model_inputs = Genome::Model::Input->get(
        value_id => $self->id,
        value_class_name => $self->class,
    );

    my @build_inputs = Genome::Model::Build::Input->get(
        value_id => $self->id,
        value_class_name => $self->class,
    );

    my @inputs = (@model_inputs, @build_inputs);

    return (scalar @inputs) ? 1 : 0;
}

sub builds_are_used_as_model_or_build_input {
    my $self = shift;

    my @builds = $self->builds;

    return grep { $_->is_used_as_model_or_build_input } @builds;
}

sub _preprocess_subclass_description {
    my ($class, $desc) = @_;
    my @names = keys %{ $desc->{has} };
    for my $prop_name (@names) {
        my $prop_desc = $desc->{has}{$prop_name};
        # skip old things for which the developer has explicitly set-up indirection
        next if $prop_desc->{id_by};
        next if $prop_desc->{via};
        next if $prop_desc->{reverse_as};
        next if $prop_desc->{implied_by};
        
        if ($prop_desc->{is_param} and $prop_desc->{is_input}) {
            die "class $class has is_param and is_input on the same property! $prop_name";
        }

        if (exists $prop_desc->{'is_param'} and $prop_desc->{'is_param'}) {
            $prop_desc->{'via'} = 'processing_profile',
            $prop_desc->{'to'} = $prop_name;
            $prop_desc->{'is_mutable'} = 0;
            $prop_desc->{'is_delegated'} = 1;
            if ($prop_desc->{'default_value'}) {
                $prop_desc->{'_profile_default_value'} = delete $prop_desc->{'default_value'};
            }
        }

        if (exists $prop_desc->{'is_input'} and $prop_desc->{'is_input'}) {

            my $assoc = $prop_name . '_association' . ($prop_desc->{is_many} ? 's' : '');
            next if $desc->{has}{$assoc};

            $desc->{has}{$assoc} = {
                property_name => $assoc,
                implied_by => $prop_name,
                is => 'Genome::Model::Input',
                reverse_as => 'model', 
                where => [ name => $prop_name ],
                is_mutable => $prop_desc->{is_mutable},
                is_optional => $prop_desc->{is_optional},
                is_many => 1, #$prop_desc->{is_many},
            };

            # We hopefully don't need _id accessors
            # If we do duplicate the code below for value_id

            %$prop_desc = (%$prop_desc,
                via => $assoc, 
                to => 'value',
            );
        }
    }

    my ($ext) = ($desc->{class_name} =~ /Genome::Model::(.*)/);
    my $pp_subclass_name = 'Genome::ProcessingProfile::' . $ext;
    
    my $pp_data = $desc->{has}{processing_profile} = {};
    $pp_data->{data_type} = $pp_subclass_name;
    $pp_data->{id_by} = ['processing_profile_id'];

    $pp_data = $desc->{has}{processing_profile_id} = {};
    $pp_data->{data_type} = 'Number';

    return $desc;
}

sub params_for_class {
    my $meta = shift->class->__meta__;
    
    my @param_names = map {
        $_->property_name
    } sort {
        $a->{position_in_module_header} <=> $b->{position_in_module_header}
    } grep {
        defined $_->{is_param} && $_->{is_param}
    } $meta->property_metas;
    
    return @param_names;
}

sub _resolve_type_name_for_class {
    my $class = shift;
    my ($subclass) = $class =~ /^Genome::Model::([\w\d]+)$/;
    return unless $subclass;
    return Genome::Utility::Text::camel_case_to_string($subclass);
}

1;

