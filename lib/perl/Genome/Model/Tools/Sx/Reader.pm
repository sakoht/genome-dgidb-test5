package Genome::Model::Tools::Sx::Reader;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Sx::Reader {
    has => [
        config => { is => 'Text', is_many => 1, is_optional => 1, },
        #metrics => { is_optional => 1, },
    ],
};

sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    return if not $self;

    if ( not $self->config ) { 
        return $self->_open_stdin_ref_reader;
    }

    my @readers;
    for my $config ( $self->config ) {
        my %params = $self->_parse_reader_config($config);
        return if not %params;

        my $cnt = ( exists $params{cnt} ? delete $params{cnt} : 1 );

        my $reader_class = $self->_reader_class_for_type( delete $params{type} );
        return if not $reader_class;
        $self->status_message('reader => '.$reader_class);

        my $reader = $reader_class->create(%params);
        if ( not $reader ) {
            $self->error_message('Failed to create '.$reader_class);
            return;
        }
        for ( 1..$cnt ) {
            push @readers, $reader;
        }
    }

    $self->{_readers} = \@readers;

    return $self;
}

sub _parse_reader_config {
    my ($self, $config) = @_;

    Carp::confess('No config to parse') if not $config;

    $self->status_message('Parsing reader config: '.$config);
    my %params;
    my (@tokens) = split(':', $config);
    if ( not @tokens ) {
        $self->error_message("Failed to split config: $config");
        return;
    }

    for my $token ( @tokens ) {
        my ($key, $value) = split('=', $token);
        if ( defined $value ) {
            $params{$key} = $value;
            next;
        }
        if ( $params{file} ) {
            $self->error_message('Multiple values for "file" in config');
            return;
        }
        $params{file} = $key;
    }

    if ( not $params{file} ) {
        $self->error_message('Failed to get "file" from config');
        return;
    }

    if ( not $params{type} ) {
        $params{type} = $self->_type_for_file($params{file});
        return if not $params{type};
    }

    $self->status_message('Config: ');
    for my $key ( keys %params ) {
        $self->status_message($key.' => '.$params{$key});
    }

    return %params;
}

sub _type_for_file {
    my ($self, $file) = @_;

    Carp::confess('No file to get type') if not $file;

    my ($ext) = $file =~ /\.(\w+)$/;
    if ( not $ext ) {
        $self->error_message('Failed to get extension for file: '.$file);
        return;
    }

    my %file_exts_and_formats = (
        fastq => 'sanger',
        fasta => 'phred',
        fna => 'phred',
        fa => 'phred',
    );
    if ( $file_exts_and_formats{$ext} ) {
        return $file_exts_and_formats{$ext}
    }

    $self->error_message('Failed to get type for file: '.$file);
    return;
}


sub _reader_class_for_type {
    my ($self, $type) = @_;

    Carp::confess('No type to get reader class') if not $type;

    my %types_and_classes = (
        phred => 'PhredReader',
        sanger => 'FastqReader',
        illumina => 'IlluminaFastqReader',
        'ref' => 'StdinRefReader',
    );

    if ( exists $types_and_classes{$type} ) {
        my $reader_class = 'Genome::Model::Tools::Sx::'.$types_and_classes{$type};
        return $reader_class;
    }

    $self->error_message('Invalid type: '.$type);
    return;
}

sub read {
    my $self = shift;

    my @seqs;
    for my $reader ( @{$self->{_readers}} ) {
        my $seq = $reader->read;
        next if not $seq;
        push @seqs, $seq;
    }
    return if not @seqs;

    #$self->metrics->add(\@seqs) if $self->metrics and @seqs;
    
    return \@seqs;
}

1;

