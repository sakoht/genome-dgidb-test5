package UR::Command::Define::Datasource::Postgresql;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command::Define::Datasource::RDBMS",
);

sub help_brief {
   "Add a PostgreSQL data source to the current namespace."
}

sub _write_dbname { 1 }

sub _data_source_sub_class_name {
    "UR::DataSource::PostgreSQL"
}

sub execute {
    my $self = shift;

    $self->error_message("postponed until later, use 'ur define datasource rdbms' for now");
    return 0;
}

1;

