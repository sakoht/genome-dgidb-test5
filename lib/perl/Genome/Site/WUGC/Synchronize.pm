package Genome::Site::WUGC::Synchronize;

# TODO Lots of redundant code here that can be refactored away

use strict;
use warnings;
use Genome;
use Carp 'confess';

my $low = 20_000;
my $high = 200_000;
UR::Context->object_cache_size_highwater($high);
UR::Context->object_cache_size_lowwater($low);

class Genome::Site::WUGC::Synchronize {
    is => 'Genome::Command::Base',
    has_optional => [
        report_file => {
            is => 'FilePath',
            doc => 'If provided, extra information is recorded in this file'
        },
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
};

# Maps new classes to old classes. Abstract classes should not be included here because 
# it can lead to some attributes not being copied over.
sub objects_to_sync {
    return (
        'Genome::InstrumentData::454' => 'Genome::Site::WUGC::InstrumentData::454',
        'Genome::InstrumentData::Sanger' => 'Genome::Site::WUGC::InstrumentData::Sanger',
        'Genome::InstrumentData::Solexa' => 'Genome::Site::WUGC::InstrumentData::Solexa',
        'Genome::InstrumentData::Imported' => 'Genome::Site::WUGC::InstrumentData::Imported',
        'Genome::Individual' => 'Genome::Site::WUGC::Individual',
        'Genome::PopulationGroup' => 'Genome::Site::WUGC::PopulationGroup',
        'Genome::Taxon' => 'Genome::Site::WUGC::Taxon',
        'Genome::Sample' => 'Genome::Site::WUGC::Sample',
        'Genome::Library' => 'Genome::Site::WUGC::Library',
    );
}

# Specifies the order in which classes should be synced
sub sync_order {
    return qw/ 
        Genome::Taxon
        Genome::Individual
        Genome::PopulationGroup
        Genome::Sample
        Genome::Library
        Genome::InstrumentData::Solexa
        Genome::InstrumentData::Sanger
        Genome::InstrumentData::454
        Genome::InstrumentData::Imported
    /;
}

# For each pair of classes above, determine which objects exist in both the old and new schemas and
# copy the old objects into the new schema and report the new objects that don't exist in the old schema
sub execute {
    my $self = shift;

    # Stores copied and missing IDs for each type
    my %report;
    
    # Maps new classes with old classes
    my %types = $self->objects_to_sync;

    for my $new_type ($self->sync_order) {
        confess "Type $new_type isn't mapped to an old class!" unless exists $types{$new_type};
        my $old_type = $types{$new_type};

        for my $type ($new_type, $old_type) {
            confess "Could not get meta object for $type!" unless $type->__meta__;
        }

        $self->status_message("\nSyncing $new_type and $old_type");
        $self->status_message("Creating iterators...");
        my $new_iterator = $new_type->create_iterator;
        my $old_iterator = $old_type->create_iterator;

        my $created_objects = 0;
        my $seen_objects = 0;

        # The rows in the old/new tables have the same IDs. UR sorts these objects by their
        # IDs internally, so simply iterating over old/new objects and checking the IDs is
        # enough to determine if an object is missing.
        $self->status_message("Iterating over all objects and copying as needed");
        my $new_object = $new_iterator->next;
        my $old_object = $old_iterator->next;

        while ($new_object or $old_object) {
            $seen_objects++;
            my $object_created = 0;
            my $new_id = $new_object->id if $new_object;
            my $old_id = $old_object->id if $old_object;

            # Old iterator exhausted, record IDs of objects in new table but not in the old. In the case of
            # instrument data, this means the data may have been expunged. In other cases, apipe may need to know.
            if ($new_object and not $old_object) {
                push @{$report{$new_type}{'missing'}}, $new_id;
                $new_object = $new_iterator->next;
            }
            # New iterator exhausted, so copy any old objects still remaining.
            elsif ($old_object and not $new_object) {
                if ($self->copy_object($old_object, $new_type)) {
                    $created_objects++;
                    $object_created = 1;
                }
                push @{$report{$new_type}{'copied'}}, $old_id;
                $old_object = $old_iterator->next;
            }
            else {
                # If IDs are equal, iterate both old and new and continue
                if ($new_id eq $old_id) {
                    $new_object = $new_iterator->next;
                    $old_object = $old_iterator->next;
                }
                # If new ID is less than old ID, then we are missing an old object (since the iterator skipped over several)
                elsif ($new_id lt $old_id) {
                    push @{$report{$new_type}{'missing'}}, $new_id;
                    $new_object = $new_iterator->next;
                }
                # Old ID is less than new ID, so a new object needs to be created
                else {
                    if ($self->copy_object($old_object, $new_type)) {
                        $created_objects++;
                        $object_created = 1;
                    }
                    push @{$report{$new_type}{'copied'}}, $old_id;
                    $old_object = $old_iterator->next;
                }
            }

            # Periodic commits to prevent lost progress in case of failure
            if ($created_objects != 0 and $created_objects % 1000 == 0) {
                confess 'Could not commit!' unless UR::Context->commit;
                print STDERR "\n" and $self->print_object_cache_summary if $self->show_object_cache_summary;
            }

            print STDERR "Looked at $seen_objects objects, created $created_objects\r";
        }
        print STDERR "\n";
        
        confess 'Could not commit!' unless UR::Context->commit;
        $self->print_object_cache_summary if $self->show_object_cache_summary;
        $self->status_message("Done syncning $new_type and $old_type");
    }
    print STDERR "\n";

    $self->_report(\%report);
    $self->generate_report if defined $self->report_file;
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

# Writes a report detailing the IDs of objects that have been created/missed
sub generate_report {
    my $self = shift;
    my %report = %{$self->_report};
    $self->status_message("Generating report");

    if (-e $self->report_file) {
        unlink $self->report_file;
        $self->status_message("Removed existing report at " . $self->report_file);
    }

    my $fh = IO::File->new($self->report_file, 'w');
    if ($fh) {
        for my $type (sort keys %report) {
            $fh->print("*** Type $type ***\n");
            for my $operation (qw/ copied missing /) {
                next unless exists $report{$type}{$operation};
                $fh->print(ucfirst $operation . "\n");
                $fh->print(join("\n", @{$report{$type}{$operation}}) . "\n");
            }
        }
        $fh->close;
    }
    else {
        $self->warning_message("Could not create file handle for report file " . $self->report_file . ", not generating report");
    }
    
    $self->status_message("Report generated at " . $self->report_file);
    return 1;
}

# Create a new object of the given class based on the given object
sub copy_object {
    my ($self, $original_object, $new_object_class) = @_;
    my $method_base = lc $new_object_class;
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
        my $property_name = $property->property_name;
        my $value = $original_object->{$property_name};
        next if @ignore and grep { $property_name eq $_ } @ignore;
        next unless defined $value;

        my $via = $property->via;
        if (defined $via and $via eq 'attributes') {
            $indirect_properties{$property_name} = $value;
        }
        else {
            $direct_properties{$property_name} = $value;
        }
    }

    return (\%direct_properties, \%indirect_properties);
}

# Below are type-specific create methods. They are each responsible for taking an object and a class
# and creating a new object of the given class based on the given object.
sub _create_genome_instrumentdata_imported {
    my ($self, $original_object, $new_object_class) = @_;

    my ($direct_properties, $indirect_properties) = $self->_get_direct_and_indirect_properties_for_object(
        $original_object,
        $new_object_class, 
        qw/ sample_name sample_id _old_sample_name _old_sample_id /
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

    for my $name (sort keys %{$indirect_properties}) {
        Genome::InstrumentDataAttribute->create(
            instrument_data_id => $object->id,
            attribute_label => $name,
            attribute_value => $indirect_properties->{$name}, 
        )
    }

    return 1;
}

sub _create_genome_instrumentdata_solexa {
    my ($self, $original_object, $new_object_class) = @_;
    
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

    for my $name (sort keys %{$indirect_properties}) {
        Genome::InstrumentDataAttribute->create(
            instrument_data_id => $object->id,
            attribute_label => $name,
            attribute_value => $indirect_properties->{$name}, 
        )
    }

    return 1;
}

sub _create_genome_instrumentdata_sanger {
    my ($self, $original_object, $new_object_class) = @_;

    # Some sanger instrument don't have a library. If that's the case here, just don't create the object
    return 0 unless defined $original_object->library_id or defined $original_object->library_name or defined $original_object->library_summary_id;
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

    for my $name (sort keys %{$indirect_properties}) {
        Genome::InstrumentDataAttribute->create(
            instrument_data_id => $object->id,
            attribute_label => $name,
            attribute_value => $indirect_properties->{$name}, 
        );
    }

    return 1;
}

sub _create_genome_instrumentdata_454 {
    my ($self, $original_object, $new_object_class) = @_;

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

    for my $name (sort keys %{$indirect_properties}) {
        Genome::InstrumentDataAttribute->create(
            instrument_data_id => $object->id,
            attribute_label => $name,
            attribute_value => $indirect_properties->{$name}, 
        );
    }
    
    # TODO Need to talk to Scott about how to go about dumping SFF files. Currently, this info is stored in a
    # LIMS table and dumped to the filesystem as an SFF file on demand, see Genome::InstrumentData::454->sff_file.
    # The sff_file method uses GSC::* objects and will need to be moved to Genome/Site/WUGC. To accomplish this, 
    # we can either dump all SFF files from the db and add the dumping logic here in the sync tool, or we can forego
    # the mass dumping and do it manually as needed (it would still be done here as the data is synced).

    return 1;
}

sub _create_genome_sample {
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

    for my $property_name (sort keys %{$indirect_properties}) {
        Genome::SubjectAttribute->create(
            subject_id => $object->id,
            attribute_label => $property_name,
            attribute_value => $indirect_properties->{$property_name},
        );
    }

    return 1;
}

sub _create_genome_populationgroup {
    my ($self, $original_object, $new_object_class) = @_;

    # No attributes/indirect properties, etc to worry about here (except members, below)
    my %params;
    for my $property ($new_object_class->__meta__->properties) {
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

sub _create_genome_library {
    my ($self, $original_object, $new_object_class) = @_;

    my %params;
    for my $property ($new_object_class->__meta__->properties) {
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

sub _create_genome_individual {
    my ($self, $original_object, $new_object_class) = @_;
    return $self->_create_genome_taxon($original_object, $new_object_class);
}

sub _create_genome_taxon {
    my ($self, $original_object, $new_object_class) = @_;

    my %params;
    for my $property ($new_object_class->__meta__->properties) {
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

1;

