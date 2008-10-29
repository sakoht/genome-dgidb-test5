
package Genome::Model::Command::Create::Model;

use strict;
use warnings;

use Genome;
use Command; 
use Genome::Model;
use File::Path;
use Data::Dumper;

class Genome::Model::Command::Create::Model {
    is => ['Genome::Model::Event'],
    sub_classification_method_name => 'class',
    has => [
        processing_profile_name     => {
                                        is => 'varchar',
                                        len => 255,
                                        doc => 'The name of the processing profile to be used. '
                                    },
        subject_name                => {
                                        is => 'varchar',
                                        len => 255,
                                        doc => 'The name of the subject all the reads originate from'
                                    },
        subject_type                => {
                                        is => 'varchar',
                                        len => 255,
                                        doc => 'The type of subject all the reads originate from'
                                    },
    ],
    has_optional => [
         #TODO: make processing_profile not a parameter, name only
         processing_profile => {
                                is => 'Genome::ProcessingProfile',
                                doc => 'Not used as a parameter',
                                id_by => 'processing_profile_id',
                            },
         model_name         => {
                                is => 'varchar',
                                len => 255,
                                doc => 'User-meaningful name for this model(default_value $SUBJECT_NAME.$PP_NAME)'
                            },
         model              => {
                                is => 'Genome::Model',
                                id_by => 'model_id',
                                doc => 'Not used as a parameter'
                            },
         data_directory     => {
                                is => 'varchar',
                                len => 255,
                                doc => 'Optional parameter representing the data directory the model should use. Will use a default if none specified.'
                            },
                 ],
    schema_name => 'Main',
};

sub help_brief {
    "create a new genome model"
}

sub help_synopsis {
    return <<"EOS"
genome-model create
                    --model-name test5
                    --subject_name ley_aml_patient1_tumor
                    --processing-profile-name nature_aml_08
EOS
}

sub help_detail {
    return <<"EOS"
This defines a new genome model.
The properties of the model determine what will happen when the add-reads command is run.

Define the processing profile to be used by name. Do not specify the
processing_profile_id as this will be looked up and overridden by the processing
profile name.

To obtain a list of available processing profiles, use genome-model list
processing-profiles.
EOS
}

sub target_class{
    return "Genome::Model";
}

sub _shell_args_property_meta {
    # exclude this class' commands from shell arguments
    return grep { 
            $_->property_name ne 'model_id'
            #not ($_->via and $_->via ne 'run') && not ($_->property_name eq 'run_id')
        } shift->SUPER::_shell_args_property_meta(@_);
}

sub command_properties{
    my $self = shift;

    return
        grep { $_ ne 'id' and $_ ne 'bare_args'}
            map { $_->property_name }
                $self->_shell_args_property_meta;
}

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);

    unless ( $self->model_name ) {
        if ($self->subject_name and $self->processing_profile_name) {
            my $subject_name = $self->_sanitize_string_for_filesystem($self->subject_name);
            unless (defined $subject_name) {
                $class->error_message("Error removing special characteres from " . $self->subject_name);
                $self->delete;
                return;
            }
            $self->model_name($subject_name .'.'. $self->processing_profile_name);
        }
    }

    my @subject_types = qw/ dna_resource_item_name species_name sample_name /;
    unless ( 
        grep { 
            defined($self->subject_type) 
            and 
            $self->subject_type eq $_ 
        } @subject_types
    ) {
        $self->error_message(
            (
                defined($self->subject_type) 
                ?  "Invalid subject type " . $self->subject_type . "."
                : "No subject type specified!"
            )
            . "  Please select one of:\n " 
            . join("\n ",@subject_types) 
            . "\n"
        );
        $self->delete;
        return;
    }

    return $self;
}

sub execute {
    my $self = shift;


    unless ($self->_get_processing_profile_from_name()) { 
        $self->event_status('Failed');
        $self->error_message("Error: Expecting 1 processing profile match." );
        return;
    }

    $self->_validate_execute_params();
    
    # generic: abstract out
    my %params = %{ $self->_extract_command_properties_and_duplicate_keys_for__name_properties() };
    
    my $obj = $self->_create_target_class_instance_and_error_check( \%params );
    unless ($obj) {
        $self->error_message("Failed to create model!");
        return;
    }

    if (my @problems = $obj->invalid) {
        $self->error_message("Invalid model!");
        $obj->delete;
        return;
    }
    
    $self->status_message("created model " . $obj->name);
    print $obj->pretty_print_text,"\n";
    
    unless ($self->_build_model_filesystem_paths($obj)) {
        $self->error_message('filesystem path creation failed');
        $obj->delete;
        return;
    }
   
    $self->result($obj);

    return $obj;
}

sub _build_model_filesystem_paths {
    my $self = shift;
    my $model = shift;

    # This is actual data directory on the filesystem
    # Currently the disk is hard coded in $model->base_parent_directory
    my $model_data_dir = $model->data_directory;
    unless ($self->create_directory($model_data_dir)) {
        $self->error_message("model data directory '$model_data_dir could' not be successfully created");
        return;
    }

    # This is a human readable(model_name) symlink to the model_id based directory
    # This symlink is created so humans can find their data on the filesystem
    my $model_link = $model->model_link;
    if (-l $model_link) {
        $self->warning_message("model symlink '$model_link' already exists");
        unless (unlink $model_link) {
            $self->error_message("existing model symlink '$model_link' could not be removed");
            return;
        }
    }
    unless (symlink($model_data_dir,$model_link)) {
        $self->error_message("model symlink '$model_link => $model_data_dir'  could not be successfully created");
        return;
    }
    return 1;
}

sub _extract_command_properties_and_duplicate_keys_for__name_properties{
    my $self = shift;
    
    my $target_class = $self->target_class; 
    my %params;
    
    for my $command_property ($self->command_properties) {
        my $value = $self->$command_property;
        next unless defined $value;

        # This is an ugly hack just for creating Genome::Model objects
        # Command-derived objects gobble up the --name parameter as part of the
        # UR framework initialization, so we're stepping around that by
        # knowing that Genome::Model's have names, and the related Command
        # param is called "model_name"
        if ($command_property eq 'model_name') {
            if ($target_class->can('name')) {
                $params{'name'} = $value;
            }
        } else {
            # processing_profile_name is only used to grab the processing_profile... so dont include it as a param
            unless ($command_property eq 'processing_profile_name') { 
                my $object_property = $command_property;
                if ($target_class->can($command_property . "_name")) {
                    $object_property .= "_name";
                }
                $params{$object_property} = $value;
            }
        }
    }
    
    return \%params;
}

sub _validate_execute_params{
    my $self = shift;

    my $ref = $self->bare_args;
    if (($ref) && (my @args = @$ref)) {
        $self->error_message("extra arguments: @args");
        $self->usage_message($self->help_usage);
        return;
    }
}

sub _create_target_class_instance_and_error_check{
    my ($self, $params_in) = @_;
    
    my %params = %{$params_in};
    
    my $target_class = $self->target_class;    
    my $target_class_meta = $target_class->get_class_object; 
    my $type_name = $target_class_meta->type_name;
    
    $self->set(
        date_scheduled  => $self->_time_now(),
        date_completed  => undef,
        event_status    => 'Scheduled',
        event_type      => $self->command_name,
        lsf_job_id      => undef, 
        user_name       => $ENV{USER}, 
    );

    my $obj = $target_class->create(%params);
    if (!$obj) {
        $self->error_message(
            "Error creating $type_name: " 
            . $target_class->error_message
        );
        return;
    }

    $self->model($obj);

    if (my @problems = $obj->invalid) {
        $self->error_message("Error creating $type_name:\n\t"
            . join("\n\t", map { $_->desc } @problems)
            . "\n");
        $obj->delete;
        return;
    }   

    $self->date_completed($self->_time_now());
    unless($obj) {
        $self->event_status('Failed');
        $self->error_message("Failed to create genome model: " . $obj->error_message);
        print Dumper(\%params);
        return;
    }
    
    $self->event_status('Succeeded');
    return $obj;
}

# Retreives the processing profile matching the name specified
sub _get_processing_profile_from_name {
    my $self = shift;
    my $processing_profile_name = $self->processing_profile_name;
    my @processing_profiles = Genome::ProcessingProfile->get(name => $processing_profile_name);

    # Bomb out unless exactly 1 matching processing profile is found
    my $num_processing_profiles = scalar(@processing_profiles);
    unless($num_processing_profiles == 1) {
        return 0;
    }

    my $pp = $processing_profiles[0];
    $self->processing_profile_id($pp->id);
    return $pp->id; 
}


sub _sanitize_string_for_filesystem {
    my $self = shift;
    my $string = shift;
    return $string if not defined $string;
    my $OK_CHARS = '-a-zA-Z0-9_./';
    $string =~ s/[^$OK_CHARS]/_/go;
    return $string;
}
1;

