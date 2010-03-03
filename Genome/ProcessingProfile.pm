package Genome::ProcessingProfile;

use strict;
use warnings;
use Genome;

use Carp 'confess';
use Data::Dumper 'Dumper';
require Genome::Utility::Text;

class Genome::ProcessingProfile {
    table_name => 'PROCESSING_PROFILE',
    is_abstract => 1,
    attributes_have => [
        is_param => { is => 'Boolean', is_optional => 1 }
    ],
    sub_classification_method_name => '_resolve_subclass_name',
    id_by => [
        id => { is => 'NUMBER', len => 11 },
    ],
    has => [
        name      => { is => 'VARCHAR2', is_optional => 1, len => 255, doc => 'Human readable name', },
        type_name => { is => 'VARCHAR2', is_optional => 1, len => 255, is_optional => 1, doc => 'The type of processing profile' },
        supersedes => {
                       via => 'params',
                       to => 'value',
                       where => [ name => 'supersedes' ],
                       is_optional => 1,
                       is_mutable => 1,
                       doc => "The processing profile replaces the one named here.",
                   },
    ],
    has_many_optional => [
        params => { is => 'Genome::ProcessingProfile::Param', reverse_id_by => 'processing_profile' },
        models => { is => 'Genome::Model', reverse_id_by => 'processing_profile' },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
    subclass_description_preprocessor => '_expand_param_properties'
};

### Developer API ###

sub _initialize_model {
    # my ($self,$model) = @_;
    # override in sub-classes to get custom mods to the model
    return 1;
}

sub _initialize_build {
    # my ($self,$model) = @_;
    # override in sub-classes to get custom mods to the build
    return 1;
}

sub _resolve_workflow_for_build {
    my ($self,$build, $optional_lsf_queue) = @_;
    
    # override in sub-classes to return the correct workflow
    # for now this is build specific, but should eventually be pp specific,
    # and hopefully pp-subclass specific.

    if ($self->can('_execute_build')) {
        # NOTE: this workflow doesn't actually run yet.
        # Instead the runner will detect it and just execute the Perl code.
        my $workflow = Workflow::Model->create(
            name => $self->__display_name__,
            input_properties => [
                # TODO: should the workflow decide how to turn build inputs and params
                # into the inputs to the next steps?
                'build',
            ],
            output_properties => [
                'build'
            ]
        );
        return $workflow;
    }

    my $msg = sprintf(
        "\nFailed to either implement _execute_build, or override _resolve_workflow_for_build, in processing profile %s!\n"
        . " for build %s of model %s\n"
        . "And failed to ..\n",
        $self->__display_name__,
        $build->__display_name__,
        $build->model->__display_name__
    );
    Carp::confess($msg);
}

# override in sub-classes if you want a non-workflow build
#sub _execute_build {
#   # my ($self,$build, $optional_lsf_queue) = @_;
#    
#    return;
#}

###

sub create {
    my ($class, %params) = @_;

    $class->_validate_name_and_uniqueness($params{name})
        or return;

    my $subclass;
    if ( $params{type_name} ) {
        $subclass = $class->_resolve_subclass_name_for_type_name($params{type_name});
        unless ( $subclass ) {
            confess "Can't resolve subclass for type name ($params{type_name})";
        }
    }
    else {
        confess __PACKAGE__ . " is a abstract base class, and no type name was provided to resolve to the appropriate subclass" 
            if $class eq __PACKAGE__;
        $subclass = $class;
        $params{type_name} = $class->_resolve_type_name_for_class;
    }

    # Make sure subclass is a real class
    my $meta;
    eval {
        $meta = $subclass->__meta__;
    };
    unless ( $meta ) {
        confess "Can't find meta for class ($subclass). Is type name ($params{type_name}) valid?";
    }

    # Go thru params - set defaults, validate required and valid values
    foreach my $property_name ( $subclass->params_for_class ) {
        my $property_meta = $meta->property_meta_for_name($property_name);
        if ( !defined $params{$property_name} ) {
            my $default_value = $property_meta->default_value;
            if ( defined $default_value ) {
                $params{$property_name} = $default_value;
                # let this fall thru to check valid values
            }
            elsif ( $property_meta->is_optional ) {
                next;
            }
            else {
                $class->error_message(
                    sprintf('Invalid value (undefined) for %s', $property_name)
                );
                return;
            }
        }
        next unless defined $property_meta->valid_values; 
        unless ( grep { $params{$property_name} eq $_ } @{ $property_meta->valid_values } ) {
            $class->error_message(
                sprintf(
                    'Invalid value (%s) for %s.  Valid values: %s.',
                    $params{$property_name},
                    $property_name,
                    join(', ', @{ $property_meta->valid_values }),
                )
            );
            return;
        }
    }

    # Identical PPs
    $subclass->_validate_no_existing_processing_profiles_with_idential_params(%params)
        or return;

    # Create
    my $self = $class->SUPER::create(%params)
       or return;
   
    
    return $self;
}

sub _validate_name_and_uniqueness {
    my ($class, $name) = @_;

    # defined? 
    unless ( $name ) {
        # TODO resolve??
        $class->error_message("No name provided for processing profile");
        return;
    }

    # Is name unique?
    my ($existing_name_pp) = $class->get(name => $name);
    if ( $existing_name_pp ) {
        Genome::ProcessingProfile::Command::Describe->execute(
            processing_profile_id => $existing_name_pp->id,
        ) or confess "Can't create describe command to show existing processing profile";
        $class->error_message("Processing profile (above) with same name ($name) already exists.");
        return;
    }

    return 1;
}

sub _validate_no_existing_processing_profiles_with_idential_params {
    my ($subclass, %params) = @_;

    # If no params, no need to check
    my @params_for_class = $subclass->params_for_class;
    return 1 unless @params_for_class;

    # Remove these params.
    my $type_name = delete $params{type_name};
    delete $params{name};
    delete $params{supersedes};
    
    # Get all existing pps
    my @existing_pps = $subclass->get(type_name => $type_name);
    return 1 unless @existing_pps; # none ok

    # Go through each one, aking sure that the params don't match. Some params may be undef
    #  in the existing one, then defined in the new one (and vioce versa)
    EXISTING_PP: for my $existing_pp ( @existing_pps ) {
        PARAM: for my $param ( @params_for_class ) {
            my $existing_param_value = $existing_pp->$param;
            if ( not defined $params{$param} ) {
                next PARAM if not defined $existing_param_value; # both undef -> next PARAM
                next EXISTING_PP; # new is def and existing is not -> next EXISTING_PP
            }

            if ( not defined $existing_param_value ) {
                next EXISTING_PP; # new param is defined and existing is not -> next EXISTING_PP
            }

            if ( $params{$param} ne $existing_param_value ) { 
                next EXISTING_PP; # different -> next EXISTING_PP
            }
            # both are the same -> automatically goes to next PARAM
        }

        # If we get here we have one that is identical, describe and return undef
        Genome::ProcessingProfile::Command::Describe->execute(
            processing_profile_id => $existing_pp->id,
        ) or confess "Can't execute describe command to show existing processing profile";
        $subclass->error_message("Found a processing profile with the same params as the one requested to create, but with a different name.  Please use this profile, or change a param.");
        return;
    }

    # No pps found with new params, yay!
    return 1;
}

sub delete {
    my $self = shift;
    
    # Check if there are models connected with this pp
    if ( Genome::Model->get(processing_profile_id => $self->id) ) {
        $self->error_message(
            sprintf(
                'Processing profile (%s <ID: %s>) has existing models and cannot be removed. Delete the models first, then remove this processing profile',
                $self->name,
                $self->id,
            )
        );
        return;
    }
 

    # Delete params
    for my $param ( $self->params ) {
        unless ( $param->delete ) {
            $self->error_message(
                sprintf(
                    'Can\'t delete param (%s: %s) for processing profile (%s <ID: %s>), ',
                    $param->name,
                    $param->value,
                    $self->name,
                    $self->id,
                )
            );
            for my $param ( $self->params ) {
                $param->resurrect if $param->isa('UR::DeletedRef');
            }
            return;
        }
    }   

    $self->SUPER::delete
        or return;

    return 1;
}


#< Params >#
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

sub param_summary {
    my $self = shift;
    my @params = $self->params_for_class();
    my $summary;
    for my $param (@params) {
        my @values;
        eval { @values = $self->$param(); };

        if (@values == 0) {
            next;
        }
        elsif (not defined $values[0] or $values[0] eq '') {
            next; 
        };

        if (defined $summary) {
            $summary .= ' '
        }
        else {
            $summary = ''
        }

        $summary .= $param . '=';
        if ($@) {
            $summary .= '!ERROR!';
        } 
        elsif (@values > 1) {
            $summary .= join(",",@values)
        } 
        elsif ($values[0] =~ /\s/) {
            $summary .= '"$values[0]"'
        }
        else {
            $summary .= $values[0]
        }
    }
    return $summary;
}

#< SUBCLASSING >#
# This is called by the infrastructure to appropriately classify abstract processing profiles
# according to their type name because of the "sub_classification_method_name" setting
# in the class definiton...
sub _resolve_subclass_name {
    my $class = shift;

    my $type_name;
    if ( ref($_[0]) and $_[0]->can('type_name') ) {
        $type_name = $_[0]->type_name;
    } else {
        my %params = @_;
        $type_name = $params{type_name};
    }

    unless ( $type_name ) {
        my $rule = $class->get_rule_for_params(@_);
        $type_name = $rule->specified_value_for_property_name('type_name');
    }

    if ( defined $type_name ) {
        my $subclass_name = $class->_resolve_subclass_name_for_type_name($type_name);
        my $sub_classification_method_name = $class->get_class_object->sub_classification_method_name;
        if ($sub_classification_method_name) {
            if ( $subclass_name->can($sub_classification_method_name)
                 eq $class->can($sub_classification_method_name)) {
                return $subclass_name;
            } else {
                return $subclass_name->$sub_classification_method_name(@_);
            }
        } else {
            return $subclass_name;
        }
    } else {
        return undef;
    }
}

sub _resolve_subclass_name_for_type_name {
    my ($class,$type_name) = @_;
    confess "No type name givent to resolve subclass name" unless $type_name;
    return 'Genome::ProcessingProfile::'.Genome::Utility::Text::string_to_camel_case($type_name);
}

sub _resolve_type_name_for_class {
    my $class = shift;
    my ($subclass) = $class =~ /^Genome::ProcessingProfile::([\w\d]+)$/;
    return unless $subclass;
    return Genome::Utility::Text::camel_case_to_string($subclass);
}

sub _expand_param_properties {
    my ($class, $desc) = @_;
    
    while (my ($prop_name, $prop_desc) = each(%{ $desc->{has} })) {
        if (exists $prop_desc->{'is_param'} and $prop_desc->{'is_param'}) {
            $prop_desc->{'to'} = 'value';
            $prop_desc->{'is_delegated'} = 1;
            $prop_desc->{'where'} = [
                'name' => $prop_name
            ];
            $prop_desc->{'via'} = 'params';
        }
    }

    return $desc;
}

sub _resolve_log_resource {
    my ($self, $event) = @_;
    $event->create_log_directory; # dies upon failure
    return ' -o '.$event->output_log_file.' -e '.$event->error_log_file;
}





1;
