package Genome::Model::Tools::Bowtie;

use strict;
use warnings;

use Genome;
use Data::Dumper;
use File::Temp;

my $BOWTIE_DEFAULT = '0.12.5';

class Genome::Model::Tools::Bowtie {
    is => ['Command'],
    has_optional => [
        use_version => {
                    is    => 'string',
                    doc   => 'version of Bowtie application to use',
                    default_value => $BOWTIE_DEFAULT
                },
        _tmp_dir => {
                    is => 'string',
                    doc => 'a temporary directory for storing files',
                },
    ],
    doc => 'tools to work with the Bowtie aliger'
};

sub help_detail {                           # This is what the user will see with --help <---
    return <<EOS

EOS
}

my %BOWTIE_VERSIONS = (
    '0.12.5' => '/gsc/pkg/bio/bowtie/bowtie-0.12.5',
    '0.12.1' => '/gsc/pkg/bio/bowtie/bowtie-0.12.1',
    '0.10.0.2' => '/gsc/pkg/bio/bowtie/bowtie-0.10.0.2',
    '0.9.9.2' => '/gsc/pkg/bio/bowtie/bowtie-0.9.9.2',
    '0.9.8' => '/gsc/pkg/bio/bowtie/bowtie-0.9.8',
    '0.9.4' => '/gsc/pkg/bio/bowtie/bowtie-0.9.4',
);

sub path_for_bowtie_version {
    my ($class, $version) = @_;
    $version ||= $BOWTIE_DEFAULT;
    my $path = $BOWTIE_VERSIONS{$version};
    if (defined($path)) {
        if (Genome::Config->arch_os =~ /64/) {
            $path .= '-64';
        }
        return $path;
    }
    die 'No path found for bowtie version: '.$version;
}

sub default_bowtie_version {
    die "default bowtie version: $BOWTIE_DEFAULT is not valid" unless $BOWTIE_VERSIONS{$BOWTIE_DEFAULT};
    return $BOWTIE_DEFAULT;
}

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    unless ($self->arch_os =~ /64/) {
        $self->error_message('Most Bowtie tools must be run from 64-bit architecture');
        return;
    }
    unless ($self->temp_directory) {
        my $base_temp_directory = Genome::Utility::FileSystem->base_temp_directory;
        my $temp_dir = File::Temp::tempdir($base_temp_directory .'/Bowtie-XXXX', CLEANUP => 1);
        Genome::Utility::FileSystem->create_directory($temp_dir);
        $self->_tmp_dir($temp_dir);
    }
    return $self;
}


1;

