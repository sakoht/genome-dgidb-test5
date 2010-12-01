package Genome::InstrumentData::Command::Dacc::Import;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
require File::Basename;
require File::Path;

class Genome::InstrumentData::Command::Dacc::Import {
    is  => 'Genome::InstrumentData::Command::Dacc',
    is_abstract => 1,
};

sub help_brief {
    return 'Import dl\'d instrument data from the DACC';
}

sub help_detail {
    return help_brief();
}

sub execute {
    my $self = shift;

    $self->status_message('Import: '.$self->sra_sample_id.' '.$self->format);

    my $sample = $self->_get_sample;
    if ( not $sample ) {
        $self->error_message('Cannot get sample for '.$self->sra_sample_id);
        return;
    }

    my @instrument_data = $self->_get_instrument_data;
    if ( @instrument_data ){
        $self->error_message('No instrument data for sra id: '.$self->sra_sample_id);
        return;
    }

    my $been_imported = $self->has_instrument_data_been_imported;
    return if $been_imported;

    my $dl_dir = $self->_dl_directory_exists;
    return if not $dl_dir;

    my @data_files = $self->existing_data_files;
    if ( not @data_files ) {
        $self->error_message("There are not any data files in download directory: $dl_dir");
        return;
    }

    my $md5s_ok = $self->_validate_md5;
    return if not $md5s_ok;

    my $update_library = $self->_update_library;
    return if not $update_library;

    my $sub_execute_ok = $self->_execute;
    return if not $sub_execute_ok;

    $self->_reallocate; # ignore error

    $self->status_message('Import...OK');

    return 1;
}

sub _reallocate {
    my $self = shift;

    $self->status_message('Reallocate...');

    my $allocation = $self->_allocation;
    if ( not $allocation ) {
        Carp::confess('No main allocation');
    }
    if ( not $allocation->reallocate ) { # disregard error
        $self->error_message('Failed to reallocate main allocation: '.$allocation->id);
    }

    $self->status_message('Reallocate...OK');

    return 1;
}

1;

