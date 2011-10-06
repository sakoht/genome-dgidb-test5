package Genome::Model::Tools::Sx::Reader;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Sx::Reader {
    has => [
        config => { is => 'Text', is_many => 1, },
        metrics => { is => 'Genome::Model::Tools::Sx::Metrics', is_optional => 1, },
    ],
};

sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    return if not $self;

    my @config = grep { defined } $self->config;
    if ( not @config ) { 
        $self->error_message('No config given to read');
        return;
    }

    if ( grep { $_ =~ /stdinref/ } @config ) {
        if ( @config > 1 ) {
            $self->error_message('Cannot read stdin refs and from other readers');
            return;
        }
        my $reader = Genome::Model::Tools::Sx::StdinRefReader->create;
        return if not $reader;
        $self->{_reader} = $reader;
        $self->{_strategy} = 'read_stdinref';
        return $self;
    }

    my @readers;
    for my $config ( $self->config ) {
        my %params = $self->_parse_reader_config($config);
        return if not %params;

        if ( $params{file} eq 'stdinref' ) {
            delete $params{file};
        };
        my $cnt = ( exists $params{cnt} ? delete $params{cnt} : 1 );

        my $reader_class = $self->_reader_class_for_type( delete $params{type} );
        return if not $reader_class;
        $self->status_message('reader => '.$reader_class);

        my $reader = eval{ $reader_class->create(%params) };
        if ( not $reader ) {
            $self->status_message($@) if $@;
            $self->error_message('Failed to create '.$reader_class);
            return;
        }
        for ( 1..$cnt ) {
            push @readers, $reader;
        }
    }

    $self->{_readers} = \@readers;
    $self->{_strategy} = 'read_one_from_each';

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

    if ( $file eq 'stdinref' ) {
        return 'ref';
    }

    if ( $file eq '-' ) { # STDIN defaults to sanger
        return 'sanger';
    }

    $file =~ s/\.gz$//;
    my ($ext) = $file =~ /\.(\w+)$/;
    if ( not $ext ) {
        $self->error_message('Failed to get extension for file: '.$file);
        return;
    }

    my %file_exts_and_formats = (
        fq => 'sanger',
        fastq => 'sanger',
        fasta => 'phred',
        fna => 'phred',
        fa => 'phred',
        sam => 'sam',
        bam => 'bam',
        sff => 'sff',
    );
    if ( $file_exts_and_formats{$ext} ) {
        return $file_exts_and_formats{$ext}
    }

    $self->error_message('Failed to determine type for file: '.$file);
    return;
}


sub _reader_class_for_type {
    my ($self, $type) = @_;

    Carp::confess('No type to get reader class') if not $type;

    my %types_and_classes = (
        fasta => 'PhredReader',
        phred => 'PhredReader',
        sanger => 'FastqReader',
        illumina => 'IlluminaFastqReader',
        sam => 'SamReader',
        bam => 'BamReader',
        sff => 'SffReader',
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
    my $strategy = $_[0]->{_strategy};
    my $seqs = $_[0]->$strategy;
    return if not $seqs or not @$seqs;
    $_[0]->metrics->add_sequences($seqs) if $_[0]->metrics;
    return $seqs;
}

sub read_one_from_each {
    my $self = shift;

    my @seqs;
    for my $reader ( @{$self->{_readers}} ) {
        my $seq = $reader->read;
        next if not $seq;
        push @seqs, $seq;
    }
    return \@seqs;
}

sub read_stdinref {
    return $_[0]->{_reader}->read;
}
1;

