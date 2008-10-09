
package Genome::Model::Command::Create::ProcessingProfile::MicroArrayAffymetrix;

use strict;
use warnings;

use Genome;
use File::Path;
use Data::Dumper;

class Genome::Model::Command::Create::ProcessingProfile::MicroArrayAffymetrix{
    is => 'Genome::Model::Command::Create::ProcessingProfile',
    sub_classification_method_name => 'class',
    has => [
            instrument_data              => {
                                             is => 'String',
                                             doc => 'The instrument data for this processing profile',
                                             is_optional => 1,
                                         },
        ],
    schema_name => 'Main',
};

sub _shell_args_property_meta {
    # exclude this class' commands from shell arguments
    return grep { 
            $_->property_name ne 'model_id'
            #not ($_->via and $_->via ne 'run') && not ($_->property_name eq 'run_id')
        } shift->SUPER::_shell_args_property_meta(@_);
}


sub sub_command_sort_position {
    4
}

sub help_brief {
    "create a new processing profile for micro array for affymetrix"
}

sub help_synopsis {
    return <<"EOS"
genome-model processing-profile micro-array-affymetrix create 
                                        --profile-name test5 
EOS
}

sub help_detail {
    return <<"EOS"
This defines a new processing profile for micro array.
EOS
}

sub target_class{
    return "Genome::ProcessingProfile::MicroArrayAffymetrix";
}

sub _validate_execute_params {
    my $self = shift;
    
    unless($self->SUPER::_validate_execute_params) {
        $self->error_message('_validate_execute_params failed for SUPER');
        return;                        
    }

    return 1;
}

# TODO: refactor... this is copied from create/processingprofile.pm...
sub execute {
    my $self = shift;

    $DB::single = $DB::stopper;

    # genome model specific


    unless ($self->_validate_execute_params()) {
        $self->error_message("Failed to create processing_profile!");
        return;
    }

    # generic: abstract out
    my %params = %{ $self->_extract_command_properties_and_duplicate_keys_for__name_properties() };
    
    my $obj = $self->_create_target_class_instance_and_error_check( \%params );
    unless ($obj) {
        $self->error_message("Failed to create processing_profile!");
        return;
    }
    
    if (my @problems = $obj->invalid) {
        $self->error_message("Invalid processing_profile!");
        $obj->delete;
        return;
    }
    
    $self->status_message("created processing profile " . $obj->name);
    print $obj->pretty_print_text,"\n";
    
    
    return 1;
}

1;

