package Genome::Model::Build::ErrorLogEntry;
use strict;
use warnings;
use Genome;
use Workflow;

class Genome::Model::Build::ErrorLogEntry {
    table_name => 'error_log_entry',
    schema_name => 'public',
    data_source => 'Genome::DataSource::Main',
    id_generator => '-uuid',
    id_by => [
        id => { is => 'Text' },
    ],
    has => [
        entry_date         => { is => 'DateTime' },
        auto_truncate_message => { is => 'Boolean', default => '1', is_transient => 1},
        auto_truncate_inferred_message => { is => 'Boolean', default => '1', is_transient => 1},
    ],
    has_optional => [
        message     => { is => 'Text', len => 4000, default => '' },
        line        => { is => 'Integer' },
        file        => { is => 'Text' },
        package     => { is => 'Text' },
        subroutine  => { is => 'Text' },

        #The die message is parsed with a regex to glean extra information
        inferred_message => { is => 'Text', len => 4000, default => '' },
        inferred_file => { is => 'Text' },
        inferred_line => { is => 'Integer' },

        build => { is => 'Genome::Model::Build', id_by => 'build_id' },
        build_id => { is => 'NUMBER', implied_by => 'build'},
    ],
};

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    return unless $self;

    $self->entry_date(Workflow::Time->now) unless $self->entry_date;
    $self->_auto_truncate_message if $self->auto_truncate_message;
    $self->_auto_truncate_inferred_message if $self->auto_truncate_inferred_message;

    return $self;
}

sub _auto_truncate_message {
    my $self = shift;
    my $message_max_length = $self->class->__meta__->property('message')->data_length;

    if ($message_max_length && length($self->message) > $message_max_length) {
        $self->message(substr($self->message, 0, $message_max_length));
    }
    return 1;
}

sub _auto_truncate_inferred_message {
    my $self = shift;
    my $inferred_message_max_length = $self->class->__meta__->property('inferred_message')->data_length;

    if ($inferred_message_max_length && length($self->inferred_message) > $inferred_message_max_length) {
        $self->inferred_message(substr($self->inferred_message, 0, $inferred_message_max_length));
    }
    return 1;
}

1;
