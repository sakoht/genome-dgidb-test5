package UR::DataSource::SQLite;
use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::DataSource::SQLite',
    is => ['UR::DataSource::RDBMS'],
    english_name => 'ur datasource sqlite',
    is_abstract => 1,
);

# RDBMS API

sub driver { "SQLite" }

sub server {
    my $self = shift->_singleton_object();
    $self->_init_database;
    return $self->_database_file_path;
}

sub owner { 
    undef
}

sub login {
    undef
}

sub auth {
    undef
}

sub can_savepoint { 0;}  # Dosen't support savepoints

# SQLite API

sub _schema_path {
    return shift->_database_file_path() . '-schema';
}

sub _data_dump_path {
    return shift->_database_file_path() . '-dump';
}

sub _database_file_path {
    my $self = shift->_singleton_object();
    my $path = $self->get_class_object->module_path;
    $path =~ s/\.pm$/.sqlite3/ or Carp::confess("Odd module path $path");
    return $path; 
}

sub _journal_file_path {
    my $self = shift->_singleton_object();
    return $self->_database_file_path . "-journal";
}

sub _init_database {
    my $self = shift->_singleton_object();
    my $db_file     = $self->_database_file_path;
    my $dump_file   = $self->_data_dump_path;

    my $db_time     = (stat($db_file))[9];
    my $dump_time   = (stat($dump_file))[9];  

    if (-e $db_file) {
        if ($dump_time && ($db_time < $dump_time)) {
            print "$db_time db $dump_time dump\n";
            my $bak_file = $db_file . '-bak';
            $self->warning_message("Dump file is newer than the db file.  Replacing db_file $db_file.");
            unlink $bak_file if -e $bak_file;
            rename $db_file, $bak_file;
            if (-e $db_file) {
                die "Failed to move out-of-date file $db_file out of the way for reconstruction! $!";
            }
        }
        #else {
        #   $self->debug_message("Leaving db in place.  Dump file is older.");
        #}
    }

    # NOTE: don't make this an "else", since we might go into both branches because we delete the file above.
    unless (-e $db_file) {
        # initialize a new database from the one in the base class
        # should this be moved to connect time?

        $DB::single = 1;
        
        # TODO: auto re-create things as needed based on timestamp

        my $schema_file = $self->_schema_path;

        if (-e $dump_file) {
            # create from dump
            $self->warning_message("Re-creating $db_file from $dump_file.");
            system("sqlite3 $db_file <$dump_file");
            unless (-e $db_file) {
                Carp::confess("Failed to import $dump_file into $db_file!");
            }
        }
        elsif ( (not -e $db_file) and (-e $schema_file) ) {
            # create from schema
            $self->warning_message("Re-creating $db_file from $schema_file.");
            system("sqlite3 $db_file <$schema_file");
            unless (-e $db_file) {
                Carp::confess("Failed to import $dump_file into $db_file!");
            }
        }
        elsif ($self->class ne __PACKAGE__) {
            # copy from the parent class (disabled)
            Carp::confess("No schema or dump file found for $db_file!");

            my $template_database_file = $self->SUPER::server();
            unless (-e $template_database_file) {
                Carp::confess("Missing template database file: $db_file!  Cannot initialize database for " . $self->class);
            }
            unless(File::Copy::copy($template_database_file,$db_file)) {
                Carp::confess("Error copying $db_file to $template_database_file to initialize database!");
            }
            unless(-e $db_file) {
                Carp::confess("File $db_file not found after copy from $template_database_file. Cannot initialize database!");
            }
        }
        else {
            Carp::confess("No db file found, and no dump or schema file found from which to re-construct a db file!");
        }
    }
    return 1;
}

sub _init_created_dbh
{
    my ($self, $dbh) = @_;
    return unless defined $dbh;
    $dbh->{LongTruncOk} = 0;
    # wait one minute busy timeout
    $dbh->func(1800000,'busy_timeout');
    return $dbh;
}

sub _ignore_table {
    my $self = shift;
    my $table_name = shift;
    return 1 if $table_name =~ /^(sqlite|\$|URMETA)/;
}


#sub autogenerate_id_for_class_name {
#my($self,$class) = @_;
#
#    if ($self->use_dummy_autogenerated_ids) {
#        return $self->next_dummy_autogenerated_id;
#    }
#
#    $class = ref($class) || $class;
#
#    my $key = $self->_validate_autogenerate_id_for_class_name($class);
#
#    # Sequences should have the same name as the primary key column, except change
#    # _ID to _SEQ
#    my $sequence = $key;
#    $sequence =~ s/_ID$/_SEQ/;
#
#    my $dbh = $self->get_default_dbh();
#
#    # See if the sequence generator "table" is already there
#    my $seq_table = "URMETA_" . $sequence;
#    unless ($self->{'_has_sequence_generator'}->{$seq_table} or
#            grep {$_ eq $seq_table} $self->get_table_names() ) {
#        unless ($dbh->do("CREATE TABLE $seq_table ($key integer PRIMARY KEY AUTOINCREMENT)")) {
#            die "Failed to create sequence table $seq_table for class $class: ".$dbh->errstr();
#        }
#    }
#    $self->{'_has_sequence_generator'}->{$seq_table} = 1;
#
#    unless ($dbh->do("INSERT into $seq_table values(null)")) {
#        die "Failed to INSERT into $seq_table during id autogeneration for class $class";
#    }
#
#    my $new_id = $dbh->last_insert_id();
#    unless (defined $new_id) {
#        die "last_insert_id() returned undef during id autogeneration for class $class";
#    }
#
#    unless($dbh->do("DELETE from $seq_table where $key = $new_id")) {
#        die "DELETE from $seq_table for $key $new_id failed during id autogeneration for class $class";
#    }
#
#    return $new_id;
#}

sub _get_sequence_name_for_table_and_column {
    my $self = shift->_singleton_object;
    my ($table_name,$column_name) = @_;
    
    my $dbh = $self->get_default_dbh();
    
    # See if the sequence generator "table" is already there
    my $seq_table = sprintf('URMETA_%s_%s_seq', $table_name, $column_name);
    unless ($self->{'_has_sequence_generator'}->{$seq_table} or
            grep {$_ eq $seq_table} $self->get_table_names() ) {
        unless ($dbh->do("CREATE TABLE IF NOT EXISTS $seq_table (next_value integer PRIMARY KEY AUTOINCREMENT)")) {
            die "Failed to create sequence generator $seq_table: ".$dbh->errstr();
        }
    }
    $self->{'_has_sequence_generator'}->{$seq_table} = 1;

    return $seq_table;
}

sub _get_next_value_from_sequence {
    my($self,$sequence_name) = @_;

    my $dbh = $self->get_default_dbh();

    # FIXME can we use a statement handle with a wildcard as the table name here?
    unless ($dbh->do("INSERT into $sequence_name values(null)")) {
        die "Failed to INSERT into $sequence_name during id autogeneration: " . $dbh->errstr;
    }

    my $new_id = $dbh->last_insert_id(undef,undef,$sequence_name,'next_value');
    unless (defined $new_id) {
        die "last_insert_id() returned undef during id autogeneration after insert into $sequence_name: " . $dbh->errstr;
    }

    unless($dbh->do("DELETE from $sequence_name where next_value = $new_id")) {
        die "DELETE from $sequence_name for next_value $new_id failed during id autogeneration";
    }

    return $new_id;
}


BEGIN {
    # Insert the column_info function into its namespace
    our $ADDL_METHODS_INSERTED;
    unless ($ADDL_METHODS_INSERTED++) {
        *DBD::SQLite::db::column_info = \&column_info;
        *DBD::SQLite::db::foreign_key_info = \&foreign_key_info;
    }
}

# This isn't meant to be called from this namespace.  It's inserted into SQLite's
# namespace by create_dbh.  In the long term it should probably be submitted
# back to the SQLite maintainers when it's working well
sub column_info {
    my($dbh,$catalog,$schema,$table,$column) = @_;

    # Convert the SQL wildcards to regex wildcards
    $column =~ tr/%_/*./;

    my $sth_tables = $dbh->table_info($catalog, $schema, $table, '');
    my @table_names = map { $_->{'TABLE_NAME'} } @{ $sth_tables->fetchall_arrayref({}) };

    my @columns;
    foreach my $table_name ( @table_names ) {

        my $sth = $dbh->prepare("PRAGMA table_info($table_name)")
                          or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
        $sth->execute() or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");

        while (my $info = $sth->fetchrow_hashref()) {
            my $node = {};
            $node->{'TABLE_CAT'} = $catalog;
            $node->{'TABLE_SCHEM'} = $schema;
            $node->{'TABLE_NAME'} = $table_name;
            $node->{'COLUMN_NAME'} = $info->{'name'};
            $node->{'DATA_TYPE'} = $info->{'type'};  # FIXME shouldn't this be converted to some cannonical list?
            $node->{'TYPE_NAME'} = $info->{'type'};
            $node->{'COLUMN_SIZE'} = undef;    # FIXME parse the type field to figure it out
            $node->{'NULLABLE'} = ! $info->{'notnull'};
            $node->{'IS_NULLABLE'} = ($node->{'NULLABLE'} ? 'YES' : 'NO');
            $node->{'REMARKS'} = "";
            $node->{'COLUMN_DEF'} = $info->{'dflt_value'};
            $node->{'SQL_DATA_TYPE'} = "";  # FIXME shouldn't this be something related to DATA_TYPE
            $node->{'SQL_DATETIME_SUB'} = "";
            $node->{'CHAR_OCTET_LENGTH'} = undef;  # FIXME this should be the same as column_size, right?
            $node->{'ORDINAL_POSITION'} = $info->{'cid'};

            push @columns, $node;
        }
    }

    my $sponge = DBI->connect("DBI:Sponge:", '','')
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");

    my @returned_names = qw( TABLE_CAT TABLE_SCHEM TABLE_NAME COLUMN_NAME DATA_TYPE TYPE_NAME COLUMN_SIZE
                             BUFFER_LENGTH DECIMAL_DIGITS NUM_PREC_RADIX NULLABLE REMARKS COLUMN_DEF
                             SQL_DATA_TYPE SQL_DATETIME_SUB CHAR_OCTET_LENGTH ORDINAL_POSITION IS_NULLABLE );
    my $returned_sth = $sponge->prepare("column_info $table", {
        rows => [ map { [ @{$_}{@returned_names} ] } @columns ],
        NUM_OF_FIELDS => scalar @returned_names,
        NAME => \@returned_names,
    }) or return $dbh->DBI::set_err($sponge->err(), $sponge->errstr());

    return $returned_sth;
}


# Same thing here. The UR object system only ever calls this with either a
# $pk_table or a $fk_table, but not both, so that's all we support right now
sub foreign_key_info {
my($dbh,$fk_catalog,$fk_schema,$fk_table,$pk_catalog,$pk_schema,$pk_table) = @_;

    my($table_col_fk, $table_col_fk_rev) = &_get_fk_lists($dbh);

    my @ret_data;
    if ($pk_table) {
        my $fksth = $dbh->prepare_cached("PRAGMA foreign_key_list($pk_table)")
                          or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
        $fksth->execute() or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");

        while (my $info = $fksth->fetchrow_hashref()) {
            foreach my $fk_info (@{$table_col_fk->{$pk_table}->{$info->{'from'}}}) {
                my $node = {};
                $node->{'FK_NAME'} = $fk_info->{'fk_name'};
                $node->{'FK_TABLE_NAME'} = $pk_table;
                $node->{'FK_COLUMN_NAME'} = $info->{'from'};
                $node->{'UK_TABLE_NAME'} = $info->{'table'};
                $node->{'UK_COLUMN_NAME'} = $info->{'to'};

                push(@ret_data, $node);
            }
        }
    } elsif ($fk_table) {
        # We'll have to loop through each table in the DB and find FKs that reference
        # the named table
        my @table_names = keys %$table_col_fk;

        foreach my $table_name ( @table_names ) {
            my $fksth = $dbh->prepare_cached("PRAGMA foreign_key_list($table_name)")
                          or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
            $fksth->execute();

            while (my $info = $fksth->fetchrow_hashref()) {
                next unless ($info->{'table'} eq $fk_table);

                foreach my $fk_info ( @{$table_col_fk_rev->{$fk_table}->{$info->{'to'}}} ) {
                    next unless ($fk_info->{'pk_table'} eq $table_name);
                    my $node = {};
                    $node->{'FK_NAME'} = $fk_info->{'fk_name'};
                    $node->{'FK_TABLE_NAME'} = $table_name;
                    $node->{'FK_COLUMN_NAME'} = $info->{'from'};
                    $node->{'UK_TABLE_NAME'} = $fk_table;
                    $node->{'UK_COLUMN_NAME'} = $info->{'to'};

                    push(@ret_data, $node);
                }
            }
        }
    }

        my $sponge = DBI->connect("DBI:Sponge:", '','')
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");

    my @returned_names = qw( FK_NAME UK_TABLE_NAME UK_COLUMN_NAME FK_TABLE_NAME FK_COLUMN_NAME );
    my $table = $pk_table || $fk_table;
    my $returned_sth = $sponge->prepare("foreign_key_info $table", {
        rows => [ map { [ @{$_}{@returned_names} ] } @ret_data ],
        NUM_OF_FIELDS => scalar @returned_names,
        NAME => \@returned_names,
    }) or return $dbh->DBI::set_err($sponge->err(), $sponge->errstr());

    return $returned_sth;
}


# Return a hashref of foreign key mappings keyed by primary table,
# and another keyed by referred table
sub _get_fk_lists {
my($dbh) = @_;

    my $sql = q(select name,sql from sqlite_master where type='table');
    my $sth_tables = $dbh->prepare($sql);
    return undef unless $sth_tables;

    $sth_tables->execute();

    #FIXME This needs a real SQL parser behind it to handle things like data types
    # containing commas, table wide constraints, multi-column primary keys, etc
    my($table_col_fk,$table_col_fk_rev);
    EACH_TABLE:
    while (my $row = $sth_tables->fetchrow_hashref()) {
        $row->{'sql'} =~ s/(\n)|\s+/ /g;
        my($col_str) = ($row->{'sql'} =~ m/CREATE\s+TABLE\s+\w+\s*\((.*)\)/i);
        $col_str =~ s/^\s+|\s+$//g;
        my @cols = split(',',$col_str);

        foreach my $col ( @cols ) {
            $col =~ s/^\s+|\s$//;
            # constraint declarations come after all the column declarations.
            # Better parsing of the SQL would make this not necessary
            next EACH_TABLE if ($col =~ m/^PRIMARY KEY|^NOT NULL|^UNIQUE|^CHECK|^DEFAULT|^COLLATE/i);

            my($col_name) = ($col =~ m/(\w+)\s/);  # First part is the column name
            my($fk_name, $fk_table,$fk_col) = ($col =~ m/CONSTRAINT (\w+) REFERENCES (\w+)\((\w+)\)/);
            next unless ($col_name && $fk_name && $fk_table && $fk_col);

            push(@{$table_col_fk->{$row->{'name'}}->{$col_name}},
                 { fk_name => $fk_name,
                   fk_table => $fk_table,
                   fk_col => $fk_col,
                 }
                );
            push(@{$table_col_fk_rev->{$fk_table}->{$fk_col}},
                 { fk_name => $fk_name,
                   pk_table => $row->{'name'},
                   pk_col => $col_name,
                 }
                );
        }
    }

    return ($table_col_fk, $table_col_fk_rev);
}


sub bitmap_index_info {
    # SQLite dosen't support bitmap indicies, so there aren't any
    return [];
}


sub unique_index_info {
my($self,$table_name) = @_;

    my $dbh = $self->get_default_dbh();
    return undef unless $dbh;

    # First, do a pass looking for unique indexes
    my $idx_sth = $dbh->prepare(qq(PRAGMA index_list($table_name)));
    return undef unless $idx_sth;

    $idx_sth->execute();

    my $ret = {};
    while(my $data = $idx_sth->fetchrow_hashref()) {
        next unless ($data->{'unique'});

        my $idx_name = $data->{'name'};
        my $idx_item_sth = $dbh->prepare(qq(PRAGMA index_info($idx_name)));
        $idx_item_sth->execute();
        while(my $index_item = $idx_item_sth->fetchrow_hashref()) {
            $ret->{$idx_name} ||= [];
            push( @{$ret->{$idx_name}}, $index_item->{'name'});
        }
    }

    return $ret;
}


# By default, make a text dump of the database at commit time.
# This should really be a datasource property
sub dump_on_commit {
    0;
}

# We're overriding commit from UR::DS::commit() to add the behavior that after
# the actual commit happens, we also make a dump of the database in text format
# so that can be version controlled
sub commit {
    my $self = shift;

    my $has_no_pending_trans = (!-f $self->_journal_file_path());   

    my $worked = $self->SUPER::commit(@_);
    return unless $worked;

    my $db_filename = $self->_database_file_path();
    my $dump_filename = $self->_data_dump_path();

    return 1 if ($has_no_pending_trans);
    
    return 1 unless $self->dump_on_commit or -e $dump_filename;
    
    # FIXME is there a way to do a dump from within DBI?    
    my $retval = system("sqlite3 $db_filename .dump > $dump_filename; touch $db_filename");
    if ($retval == 0) {
        # The dump worked
        return 1;
    } elsif ($? == -1) {
        $retval >>= 8;
        $self->error_message("Dumping the SQLite database $db_filename from DataSource ",$self->get_name," to $dump_filename failed\nThe sqlite3 return code was $retval, errno $!");
        return;
    }

    # Shouldn't get here...
    return;
}

1;
