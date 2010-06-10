package Genome::Model::InstrumentDataAssignment;

use strict;
use warnings;
use Genome;

class Genome::Model::InstrumentDataAssignment {
    table_name => 'MODEL_INSTRUMENT_DATA_ASSGNMNT',
    id_by => [
        model => { 
            is => 'Genome::Model',
            id_by => 'model_id',
        },
        instrument_data => { 
            is => 'Genome::InstrumentData',
            id_by => 'instrument_data_id',
        },
    ],
    has => [
        first_build_id => { is => 'NUMBER', len => 10, is_optional => 1 },
        
        filter_desc         => { is => 'Text', is_optional => 1, 
                                valid_values => ['forward-only','reverse-only',undef],
                                doc => 'limit the reads to use from this instrument data set' },
        
        first_build         => { is => 'Genome::Model::Build', id_by => 'first_build_id', is_optional => 1 },
        
        #< Attributes from the instrument data >#
        run_name            => { via => 'instrument_data'},
        
        #< Left over from Genome::Model::ReadSet >#
        # PICK ONE AND FIX EVERYTHING THAT USES THIS
        subset_name         => { via => 'instrument_data'},
        run_subset_name     => { via => 'instrument_data', to => 'subset_name'},
        
        # PICK ONE AND FIX EVERYTHING THAT USES THIS
        short_name          => { via => 'instrument_data' },
        run_short_name      => { via => 'instrument_data', to => 'short_name' },
        library_name        => { via => 'instrument_data' },
        sample_name         => { via => 'instrument_data' },
        sequencing_platform => { via => 'instrument_data' },
        full_path           => { via => 'instrument_data' },
        full_name           => { via => 'instrument_data' },
        _calculate_total_read_count     => { via => 'instrument_data' },
        unique_reads_across_library     => { via => 'instrument_data' },
        duplicate_reads_across_library  => { via => 'instrument_data' },
        median_insert_size              => { via => 'instrument_data'},
        sd_above_insert_size            => { via => 'instrument_data'},
        is_paired_end                   => { via => 'instrument_data' },
    ],
    has_many_optional => [
        events => {
            is => 'Genome::Model::Event',
            reverse_id_by => 'instrument_data_assignment',
        },
    ],
    schema_name => 'GMSchema',
    data_source => 'Genome::DataSource::GMSchema',
};

# FIXME temporary - copy model instrument data as inputs, when all 
#  inst_data is an input, this (the whole create) can be removed
sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_)
        or return;

    if ( not $self->model_id or not $self->model ) {
        $self->error_message("No model id or model.");
        #$self->delete;
        return $self;
    }
    
    if ( not $self->instrument_data_id or not $self->instrument_data ) {
        $self->error_message("No instrument data id or instrument data.");
        #$self->delete;
        return $self;
    }

    # Adding as input cuz of mock inst data
    unless ( $self->model->add_input(
            name => 'instrument_data',
            value_class_name => $self->instrument_data->class,
            value_id => $self->instrument_data->id,
        ) ) {
        $self->error_message("Can't add instrument data (".$self->instrument_data_id.") as an input to mode.");
        $self->delete;
        return;
    }

    return $self;
}

# Replace alignments() and alignment_sets() with something generic.
# The only requirement is that it returns Genome::SoftwareResults objects,
# so they can be introspected, and have an ->output directory.

# This returns any isolated, per-instrument-data results which
# are produced for a model across builds, if they exist.
# This may be alignment data, trimming results, or fully empty 
# when the instrument data is not processed in isolation at all.

sub results { 
    my $self  = shift;
    my $build = shift;  # refalign doesn't vary for instdata per build
                        # but other pipelines might
 
    my $model = $self->model;
    my $processing_profile = $model->processing_profile;
    if ($processing_profile->can('results_for_instrument_data_assignment')) {
        # support for some sort of per-instdata results is present
        return $processing_profile->results_for_instrument_data_assignment($self);
    }
    else {
        # this profile doesn't have any per-instdata results
        return;
    }
}

sub alignment_directory {
    my $self = shift;
    my ($results) = $self->results;
    return unless $results;
    return $results->output_dir;
}

# NOTE: code which triggers alignment no longer comes here.
# It passes the assignment object into the current processing profile
# which has pipeline-specific alignment logic.

sub __errors__ {
    my ($self) = shift;

    my @tags = $self->SUPER::__errors__(@_);

    unless (Genome::Model->get($self->model_id)) {
        push @tags, UR::Object::Tag->create(
                                            type => 'invalid',
                                            properties => ['model_id'],
                                            desc => "There is no model with id ". $self->model_id,
                                        );
    }

    unless (Genome::InstrumentData->get($self->instrument_data_id)) {
        push @tags, UR::Object::Tag->create(
                                            type => 'invalid',
                                            properties => ['instrument_data_id'],
                                            desc => "There is no instrument data with id ". $self->instrument_data_id,
                                        );
    }
    return @tags;
}

# TODO: remove this.  There may be multiple read length per instdata.
sub read_length {
    my $self = shift;
    my $instrument_data = $self->instrument_data;
    unless ($instrument_data) {
        die('no instrument data for id '. $self->instrument_data_id .'  '. Data::Dumper::Dumper($self));
    }
    my $read_length = $instrument_data->read_length;
    if ($read_length <= 0) {
        die("Impossible value '$read_length' for read_length field for instrument data:". $self->id);
    }
    return $read_length;
}

sub yaml_string {
    my $self = shift;
    return YAML::Dump($self);
}

sub delete {
    my $self = shift;

    #< Temp - remove input, if exists.
    #   - get input that matches this ida
    #   - delete input
    #   - delete ida 
    my $input = Genome::Model::Input->get(
        model_id => $self->model_id,
        name => 'instrument_data',
        value_id => $self->instrument_data_id,
    );
    if ( $input ) {
        $input->delete;
    }
    #>
    
    $self->warning_message('DELETING '. $self->class .': '. $self->id);
    $self->SUPER::delete;

    return 1;
}

1;

#$HeadURL$
#$Id$
