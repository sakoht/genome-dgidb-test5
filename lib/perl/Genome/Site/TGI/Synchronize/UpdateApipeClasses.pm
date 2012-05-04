package Genome::Site::TGI::Synchronize::UpdateApipeClasses;

# TODO Lots of redundant code here that can be refactored away

use strict;
use warnings;
use Genome;
use Scalar::Util;
use Carp 'confess';

class Genome::Site::TGI::Synchronize::UpdateApipeClasses {
    is => 'Genome::Command::Base',
    has_optional => [
        show_object_cache_summary => {
            is => 'Boolean',
            default => 0,
            doc => 'If set, a summary of the contents of the UR object cache is occasionally printed, useful for debugging',
        },
        _report => {
            is_transient => 1,
            doc => 'Contains hashref to report generated by the execution of this tool',
        },
    ],
    doc => 'This command contains a mapping of old LIMS-based classes to new classes that use tables in ' .
        'the MG schema and determines if anything needs to be copied over',
};

# Maps old classes to new classes. Abstract classes should not be included here because 
# it can lead to some attributes not being copied over.
sub objects_to_sync {
    return (
        'Genome::Site::TGI::InstrumentData::454' => 'Genome::InstrumentData::454',
        'Genome::Site::TGI::InstrumentData::Sanger' => 'Genome::InstrumentData::Sanger',
        'Genome::Site::TGI::InstrumentData::Solexa' => 'Genome::InstrumentData::Solexa',
        'Genome::Site::TGI::Individual' => 'Genome::Individual',
        'Genome::Site::TGI::PopulationGroup' => 'Genome::PopulationGroup',
        'Genome::Site::TGI::Taxon' => 'Genome::Taxon',
        'Genome::Site::TGI::Sample' => 'Genome::Sample',
        'Genome::Site::TGI::Library' => 'Genome::Library',
        'Genome::Site::TGI::SetupProjectResearch' => 'Genome::Project',
        'Genome::Site::TGI::SetupWorkOrder' => 'Genome::Project',
    );
}

# Specifies the order in which classes should be synced
sub sync_order {
    return qw/
        Genome::Site::TGI::Sample
        Genome::Site::TGI::SetupProjectResearch
        Genome::Site::TGI::SetupWorkOrder
        Genome::Site::TGI::Taxon
        Genome::Site::TGI::Individual
        Genome::Site::TGI::PopulationGroup
        Genome::Site::TGI::Library
        Genome::Site::TGI::InstrumentData::Solexa
        Genome::Site::TGI::InstrumentData::454
    /;

    # FIXME Currently not syncing sanger data due to a bug, needs to be fixed
    #Genome::Site::TGI::InstrumentData::Sanger
}

sub _suppress_status_messages {
    my $self = shift;

    no warnings;
    no strict 'refs';

    for my $class (qw/ 
        Genome::Model::Command::Define::Convergence
        Genome::Model::Command::Input::Update
        Genome::Model::Command::List
        Genome::ModelGroup 
        Genome::Project 
        UR::Object::Command::List
        /) {
        $class->__meta__;
        *{$class.'::status_message'} = sub{return $_[0];};
    }
    for my $class (qw/ 
        UR::Object::Command::List::Style
        /) {
        eval("use $class");
        *{$class.'::format_and_print'} = sub{return $_[0];};
    }


    return 1;
}

# For each pair of classes above, determine which objects exist in both the old and new schemas and
# copy the old objects into the new schema and report the new objects that don't exist in the old schema
sub execute {
    my $self = shift;

    # An unlock observer is added at end of execute (not here) because
    # this command periodically commits (which triggers the observer).
    my $lock = Genome::Sys->lock_resource(
        resource_lock => '/gscuser/ebelter/sychronize-update-apipe-classes',
        #resource_lock => '/gsc/var/lock/sychronize-update-apipe-classes',
        max_try => 1,
    );
    if ( not $lock ) {
        $self->error_message("Could not lock sync cron!");
        return;
    }

    # Suppress overly talkative classes
    $self->_suppress_status_messages;

    # Load instrument data successful pidfas.
    # We only sync instrument data the have a successful pidfa.
    my $load_pidfas = $self->_load_successful_pidfas;
    if ( not $load_pidfas ) {
        $self->error_message('Failed to load instruemnt data successful pidfas!');
        return;
    }

    # Stores copied and missing IDs for each type
    my %report;
    
    # Maps new classes with old classes
    my %types = $self->objects_to_sync;

    for my $old_type ($self->sync_order) {
        confess "Type $old_type isn't mapped to an new class!" unless exists $types{$old_type};
        my $new_type = $types{$old_type};

        for my $type ($new_type, $old_type) {
            confess "Could not get meta object for $type!" unless $type->__meta__;
        }

        $self->status_message("\nSyncing $new_type and $old_type");
        $self->status_message("Creating iterators...");
        # The rows in the old/new tables have the same IDs. Ordering by the ids
        # allows us to easily determine which objects are missing from either
        # LIMS or Apipe and take appropriate action.
        my ($created_objects, $seen_old, $seen_new, $found) = (qw/ 0 0 0 0 /);
        my $new_iterator = $new_type->create_iterator(-order_by => 'id');
        my $new = sub{ $seen_new++; return $new_iterator->next; };
        my $old_iterator = $old_type->create_iterator(-order_by => 'id');
        my $old = sub{ $seen_old++; return $old_iterator->next; };

        $self->status_message("Iterating over all objects and copying as needed");
        my $new_object = $new->();
        my $old_object = $old->();
        while ($new_object or $old_object) {
            my $object_created = 0;
            my $new_id = $new_object->id if $new_object;
            my $old_id = $old_object->id if $old_object;

            # Old iterator exhausted, record IDs of objects in new table but not in the old. In the case of
            # instrument data, this means the data may have been expunged. In other cases, apipe may need to know.
            if ($new_object and not $old_object) {
                push @{$report{$new_type}{'missing'}}, $new_id;
                $new_object = $new->();
            }
            # New iterator exhausted, so copy any old objects still remaining.
            elsif ($old_object and not $new_object) {
                if ($self->copy_object($old_object, $new_type)) {
                    $created_objects++;
                    $object_created = 1;
                    push @{$report{$new_type}{'copied'}}, $old_id;
                }
                $old_object = $old->();
            }
            else {
                # If IDs are equal, iterate both old and new and continue
                if ($new_id eq $old_id) {
                    $new_object = $new->();
                    $old_object = $old->();
                    $found++;
                }
                else {
                    my $cmp;
                    if (Scalar::Util::looks_like_number($new_id) and Scalar::Util::looks_like_number($old_id)) {
                        $cmp = $new_id < $old_id;
                    }
                    else {
                        $cmp = $new_id lt $old_id;
                    }

                    # If new ID is less than old ID, then we are missing an old object (since the iterator skipped over several)
                    if ($cmp) {
                        push @{$report{$new_type}{'missing'}}, $new_id;
                        $new_object = $new->();
                    }
                    # Old ID is less than new ID, so a new object needs to be created
                    else {
                        if ($self->copy_object($old_object, $new_type)) {
                            $created_objects++;
                            $object_created = 1;
                            push @{$report{$new_type}{'copied'}}, $old_id;
                        }
                        $old_object = $old->();
                    }
                }
            }

            $self->status_message($self->print_object_cache_summary) if $self->show_object_cache_summary and ($seen_old + $seen_new) % 1000 == 0;

            # Periodic commits to prevent lost progress in case of failure
            if ($created_objects != 0 and $created_objects % 1000 == 0 and $object_created) {
                confess 'Could not commit!' unless UR::Context->commit;
            }

           print STDERR "Looked at $seen_old $old_type objects. Found $found existing and created $created_objects $new_type objects\r";
        }
        print STDERR "\n";
        
        confess 'Could not commit!' unless UR::Context->commit;
        $self->print_object_cache_summary if $self->show_object_cache_summary;
        $self->status_message("Done syncning $new_type and $old_type");
    }

    UR::Context->current->add_observer(
        aspect => 'commit',
        callback => sub{
            Genome::Sys->unlock_resource(resource_lock => $lock);
        }
    );

    $self->_report(\%report);
    return 1;
}

# Looks at the UR object cache and prints out how many objects of each type are loaded
sub print_object_cache_summary {
    my $self = shift;
    for my $type (sort keys %$UR::Context::all_objects_loaded) {
        my $count = scalar keys %{$UR::Context::all_objects_loaded->{$type}};
        next unless $count > 0;
        $self->status_message("$type : $count");
    }
    return 1;
}

# Create a new object of the given class based on the given object
sub copy_object {
    my ($self, $original_object, $new_object_class) = @_;
    my $method_base = lc $original_object->class;
    $method_base =~ s/Genome::Site::TGI:://i;
    $method_base =~ s/::/_/g;
    my $create_method = '_create_' . $method_base;
    if ($self->can($create_method)) {
        return $self->$create_method($original_object, $new_object_class);
    }
    else {
        confess "Did not find method $create_method, cannot create object of type $new_object_class!";
    }
}

# Returns indirect and direct properties for an object and the values those properties hold
sub _get_direct_and_indirect_properties_for_object {
    my ($self, $original_object, $class, @ignore) = @_;
    my %direct_properties;
    my %indirect_properties;

    my @properties = $class->__meta__->properties;
    for my $property (@properties) {
        next if $property->is_calculated;
        next if $property->is_constant;
        next if $property->is_many;
        next if $property->id_by;
        next if $property->via and $property->via ne 'attributes';
    
        my $property_name = $property->property_name;
        next unless $original_object->can($property_name);
        next if @ignore and grep { $property_name eq $_ } @ignore;

        my $value = $original_object->$property_name;
        next unless defined $value;

        if ($property->via) {
            $indirect_properties{$property_name} = $value;
        }
        else {
            $direct_properties{$property_name} = $value;
        }
    }

    return (\%direct_properties, \%indirect_properties);
}

my %successful_pidfas;
sub _load_successful_pidfas {
    my $self = shift;
    print STDERR "Load instrument data successful pidfas...\n";

    # This query/hash loading takes 10-15 secs
    # Currently, the only 'output' on a pidfa pse is a genotype file, which is only valid for genotype data

    my $dbh = Genome::DataSource::GMSchema->get_default_handle;
    if ( not $dbh ) {
        $self->error_message('Failed to get dbh from gm schema!');
        return;
    }
    my $sql = <<SQL;
        select p.param_value, pseo.data_value
        from process_step_executions\@oltp pse
        inner join pse_param\@oltp p on p.pse_id = pse.pse_id and p.param_name = 'instrument_data_id'
        left join process_step_outputs\@oltp pso on pso.ps_ps_id = pse.ps_ps_id and pso.output_description = 'genotype_file'
        left join pse_data_outputs\@oltp pseo on pseo.pso_pso_id = pso.pso_id
        where pse.ps_ps_id = 3870 and pse.pr_pse_result = 'successful'
SQL

    my $sth = $dbh->prepare($sql);
    if ( not $sth ) {
        $self->error_message('Failed to prepare successful pidfa sql');
        return;
    }
    my $execute = $sth->execute;
    if ( not $execute ) {
        $self->error_message('Failed to execute successful pidfa sql');
        return;
    }
    while ( my ($instrument_data_id, $genotype_file) = $sth->fetchrow_array ) {
        $successful_pidfas{$instrument_data_id} = $genotype_file if not defined $successful_pidfas{$instrument_data_id};
    }
    $sth->finish;

    print STDERR 'Loaded '.scalar(keys %successful_pidfas).' successful PIDFAs';
    return 1;
}

sub _create_instrumentdata_solexa {
    my ($self, $original_object, $new_object_class) = @_;

    # Successful PIDFA required!
    return 0 unless $successful_pidfas{$original_object->id};
    # Bam path required!
    return 0 unless $original_object->bam_path;
    
    my ($direct_properties, $indirect_properties) = $self->_get_direct_and_indirect_properties_for_object(
        $original_object,
        $new_object_class, 
        qw/ sample_name sample_id /
    );
    
    my $object = eval {
        $new_object_class->create(
            %{$direct_properties},
            id => $original_object->id,
            subclass_name => $new_object_class,
        );
    };
    confess "Could not create new object of type $new_object_class based on object of type " .
        $original_object->class . " with id " . $original_object->id . ":\n$@" unless $object;

    my $add_attrs = $self->_add_attributes_to_instrument_data($object, $indirect_properties);
    Carp::confess('Failed to add attributes to instrument data: '.$object->__display_name__) if not $add_attrs;

    return 1;
}

sub _create_instrumentdata_sanger {
    my ($self, $original_object, $new_object_class) = @_;

    # Successful PIDFA required!
    return 0 unless $successful_pidfas{$original_object->id};
    # Some sanger instrument don't have a library. If that's the case here, just don't create the object
    return 0 unless defined $original_object->library_id or defined $original_object->library_name
        or defined $original_object->library_summary_id;

    my %library_params;
    if (defined $original_object->library_id) {
        $library_params{id} = $original_object->library_id;
    }
    elsif (defined $original_object->library_name) {
        $library_params{name} = $original_object->library_name;
    }
    else {
        $library_params{id} = $original_object->library_summary_id;
    }
    my $library = Genome::Library->get(%library_params);
    return 0 unless $library;

    my ($direct_properties, $indirect_properties) = $self->_get_direct_and_indirect_properties_for_object(
        $original_object,
        $new_object_class, 
        qw/ sample_name sample_id /
    );

    my $object = eval {
        $new_object_class->create(
            %{$direct_properties},
            library_id => $library->id,
            id => $original_object->id,
            subclass_name => $new_object_class,
        )
    };
    confess "Could not create new object of type $new_object_class based on object of type " .
        $original_object->class . " with id " . $original_object->id . ":\n$@" unless $object;

    my $add_attrs = $self->_add_attributes_to_instrument_data($object, $indirect_properties);
    Carp::confess('Failed to add attributes to instrument data: '.$object->__display_name__) if not $add_attrs;

    return 1;
}

sub _create_instrumentdata_454 {
    my ($self, $original_object, $new_object_class) = @_;

    # Successful PIDFA required!
    return 0 unless $successful_pidfas{$original_object->id};

    my ($direct_properties, $indirect_properties) = $self->_get_direct_and_indirect_properties_for_object(
        $original_object,
        $new_object_class, 
        qw/ sample_name sample_id full_path/
    );

    my $object = eval {
        $new_object_class->create(
            %{$direct_properties},
            id => $original_object->id,
            subclass_name => $new_object_class,
        )
    };
    confess "Could not create new object of type $new_object_class based on object of type " .
        $original_object->class . " with id " . $original_object->id . ":\n$!" unless $object;

    # SFF this will soon be a indirect prop, and will then be resolved above.
    if ( not $indirect_properties->{sff_file} ) {
        my $sff_file = eval{ $original_object->sff_file; };
        $indirect_properties->{sff_file} = $sff_file if $sff_file;
    }

    my $add_attrs = $self->_add_attributes_to_instrument_data($object, $indirect_properties);
    Carp::confess('Failed to add attributes to instrument data: '.$object->__display_name__) if not $add_attrs;

    return 1;
}

sub _add_attributes_to_instrument_data {
    my ($self, $instrument_data, $attrs) = @_;

    $attrs->{tgi_lims_status} = 'new';

    for my $name ( keys %{$attrs} ) {
        Genome::InstrumentDataAttribute->create(
            instrument_data_id => $instrument_data->id,
            attribute_label => $name,
            attribute_value => $attrs->{$name}, 
        );
    }

    return 1;
}

sub _create_sample {
    my ($self, $original_object, $new_object_class) = @_;

    my ($direct_properties, $indirect_properties) = $self->_get_direct_and_indirect_properties_for_object(
        $original_object,
        $new_object_class, 
    );

    # Capture attributes that are attached to the object but aren't spelled out in class definition
    for my $attribute ($original_object->attributes) {
        $indirect_properties->{$attribute->name} = $attribute->value;
    }

    my $object = eval { 
        $new_object_class->create(
            %{$direct_properties},
            id => $original_object->id, 
            subclass_name => $new_object_class
        ) 
    };
    confess "Could not create new object of type $new_object_class based on object of type " .
        $original_object->class . " with id " . $original_object->id . ":\n$@" unless $object;

    # The genotype data link doesn't have the same name between LIMS/Apipe and it isn't set as mutable, so it
    # can only be set expclitly as below.
    my $genotype_id = delete $indirect_properties->{default_genotype_seq_id};
    if (defined $genotype_id) {
        # TODO If LIMS ever figures out how to set default genotype data to none, this logic will need to be revised.
        # Currently, the organism_sample table's default_genotype_seq_id column is a foreign key, so it would be 
        # diffiult to elegantly allow none to be set.
        $object->set_default_genotype_data($genotype_id);
    }

    for my $property_name (sort keys %{$indirect_properties}) {
        Genome::SubjectAttribute->create(
            subject_id => $object->id,
            attribute_label => $property_name,
            attribute_value => $indirect_properties->{$property_name},
        );
    }

    return 1;
}

sub _create_populationgroup {
    my ($self, $original_object, $new_object_class) = @_;

    # No attributes/indirect properties, etc to worry about here (except members, below)
    my %params;
    for my $property ($new_object_class->__meta__->_legacy_properties) {
        my $property_name = $property->property_name;
        $params{$property_name} = $original_object->{$property_name} if defined $original_object->{$property_name};
    }
    
    # Grab members from old object and pass to create parameters
    my @member_ids = map { $_->id } $original_object->members;
    $params{member_ids} = \@member_ids;

    my $object = eval { 
        $new_object_class->create(
            %params, 
            id => $original_object->id, 
            subclass_name => $new_object_class
        ) 
    };
    confess "Could not create new object of type $new_object_class based on object of type " .
        $original_object->class . " with id " . $original_object->id . ":\n$@" unless $object;

    return 1;
}

sub _create_library {
    my ($self, $original_object, $new_object_class) = @_;

    my %params;
    for my $property ($new_object_class->__meta__->_legacy_properties) {
        my $property_name = $property->property_name;
        $params{$property_name} = $original_object->{$property_name} if defined $original_object->{$property_name};
    }

    my $object = eval { 
        $new_object_class->create(
            %params, 
            id => $original_object->id, 
        ) 
    };
    confess "Could not create new object of type $new_object_class based on object of type " .
        $original_object->class . " with id " . $original_object->id . ":\n$@" unless $object;

    return 1;
}

sub _create_individual {
    my ($self, $original_object, $new_object_class) = @_;
    return $self->_create_taxon($original_object, $new_object_class);
}

sub _create_taxon {
    my ($self, $original_object, $new_object_class) = @_;

    my %params;
    for my $property ($new_object_class->__meta__->_legacy_properties) {
        my $property_name = $property->property_name;
        $params{$property_name} = $original_object->{$property_name} if defined $original_object->{$property_name};
    }

    my $object = eval { 
        $new_object_class->create(
            %params, 
            id => $original_object->id, 
            subclass_name => $new_object_class
        ) 
    };
    confess "Could not create new object of type $new_object_class based on object of type " .
        $original_object->class . " with id " . $original_object->id . ":\n$@" unless $object;

    return 1;
}

sub _create_setupprojectresearch {
    my ($self, $original_object, $new_object_class) = @_;
    return $self->_create_project($original_object, $new_object_class);
}

sub _create_setupworkorder {
    my ($self, $original_object, $new_object_class) = @_;
    return $self->_create_project($original_object, $new_object_class);
}

sub _create_project {
    my ($self, $original_object, $new_object_class) = @_;

    my $object = eval { 
        $new_object_class->create(
            id => $original_object->id, 
            name => $original_object->name,
        );
    };
    if ( not $object ) {
        confess "Could not create new object of type $new_object_class based on object of type " .
            $original_object->class . " with id " . $original_object->id . ":\n$@";
    }

    return 1;
}

1;

