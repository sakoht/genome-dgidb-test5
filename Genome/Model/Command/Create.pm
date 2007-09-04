
package Genome::Model::Command::Create;

use strict;
use warnings;

use Command; 
use Genome::Model;

use Data::Dumper;

use Genome;
UR::Object::Class->define(
    class_name => __PACKAGE__, 
    is => ['Genome::Model::Event'],
    has => [
        dna_type               => { is => 'varchar', len => 255 },
        genotyper              => { is => 'varchar', len => 255 },
        genotyper_params       => { is => 'varchar', len => 255, is_optional => 1 },
        indel_finder           => { is => 'varchar', len => 255 },
        indel_finder_params    => { is => 'varchar', len => 255, is_optional => 1 },
        name                   => { is => 'varchar', len => 255 },
        prior                  => { is => 'varchar', len => 32,  is_optional => 1 },
        read_aligner           => { is => 'varchar', len => 255 },
        read_aligner_params    => { is => 'varchar', len => 255, is_optional => 1 },
        read_calibrator        => { is => 'varchar', len => 255, is_optional => 1 },
        read_calibrator_params => { is => 'varchar', len => 255, is_optional => 1 },
        reference_sequence     => { is => 'varchar', len => 255 },
        sample                 => { is => 'varchar', len => 255 },
    ],
    schema_name => 'Main',
);

sub sub_command_sort_position {
    -1
}

sub help_brief {
    "create a new genome model"
}

sub help_synopsis {
    return <<"EOS"
genome-model create
                    --name ley_aml_1_revA
                    --sample ley_aml_patient1 
                    --dna-type whole 
                    --read-calibrator none
                    --aligner maq1_6    
                    --genotyper maq1_6     
                    --indel-finder bhdsindel1 
                    --prior NCBI-human-build36 
EOS
}

sub help_detail {
    return <<"EOS"
This defines a new genome model.  Currently it equates to a directory tree on the filesystem.

The properties of the model determine what will happen when the add-reads command is run.
EOS
}

sub target_class{
    return "Genome::Model";
}

sub command_properties{
    my $self = shift;
    
    return
        grep { $_ ne 'id' and $_ ne 'bare_args'}         
            $self->get_class_object->all_property_names;
}

sub execute {
    my $self = shift;
    
    $DB::single = 1;

    # genome model specific

    unless ($self->prior) {
        $self->prior('none');
    }

    $self->_validate_execute_params();   

    # generic: abstract out
    
    my %params = %{ $self->_extract_command_properties_and_duplicate_keys_for__name_properties() };
    
    my $obj = $self->_create_target_class_instance_and_error_check( \%params );

    # move this up eventually    

    unless (UR::Context->commit) {
        $self->error_message("Failed to commit changes!");
        return;
    }
    
    $self->status_message("created model " . $obj->name);
    print $obj->pretty_print_text,"\n";
    
    return 1;
}

sub _extract_command_properties_and_duplicate_keys_for__name_properties{
    my $self = shift;
    
    my $target_class = $self->target_class; 
    my %params;
    
    for my $command_property ($self->command_properties) {
        my $value = $self->$command_property;
        next unless defined $value;

        my $object_property = $command_property;
        if ($target_class->can($command_property . "_name")) {
            $object_property .= "_name";
        }
        $params{$object_property} = $value;
    }
    
    return \%params;
}

sub _validate_execute_params{
    my $self = shift;
    
    unless ($self->reference_sequence) {
        if ($self->prior eq "none") {
            $self->error_message("No reference sequence set.  This is required w/o a prior.");
            $self->usage_message($self->help_usage);
            return;
        }
        $self->reference_sequence($self->prior);
    }

    if (my @args = @{ $self->bare_args }) {
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
        event_status    => 'completed', 
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

    $self->genome_model($obj);

    if (my @problems = $obj->invalid) {
        $self->error_message("Error creating $type_name:\n\t"
            . join("\n\t", map { $_->desc } @problems)
            . "\n");
        $obj->delete;
        return;
    }   

    unless($obj) {
        $self->error_message("Failed to create genome model: " . $obj->error_message);
        print Dumper(\%params);
        return;
    }
    
    return $obj;
}

1;

