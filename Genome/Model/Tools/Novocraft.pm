package Genome::Model::Tools::Novocraft;

use strict;
use warnings;

use Genome;
use File::Basename;

my $DEFAULT_VERSION = '2.05.20';

class Genome::Model::Tools::Novocraft {
    is => 'Command',
    has_param => [
        use_version => {
            is => 'Version',
            default_value => $DEFAULT_VERSION,
            doc => 'Version of novocraft to use. default_value='. $DEFAULT_VERSION,
        },
    ],
    has => [
        arch_os => {
                    calculate => q|
                            my $arch_os = `uname -m`;
                            chomp($arch_os);
                            return $arch_os;
                        |
                },
    ],
};

sub sub_command_sort_position { 12 }

sub help_brief {
    "Tools to run novocraft or work with its output files.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools novocraft ...    
EOS
}

sub help_detail {                           
    return <<EOS 
More information about the novocraft suite of tools can be found at http://novocraft.sourceforege.net.
EOS
}

sub novoindex_path {
    my $self = shift;
    return $self->novocraft_path .'/novoindex';
}

sub novoalign_path {
    my $self = shift;
    return $self->novocraft_path .'/novoalign';
}

sub novocraft_path {
    my $self = $_[0];
    return $self->path_for_novocraft_version($self->use_version);
}
my %NOVOCRAFT_VERSIONS = (
                    '2.03.12' => '/gsc/pkg/bio/novocraft/novocraft-2.03.12',
                    '2.04.02' => '/gsc/pkg/bio/novocraft/novocraft-2.04.02',
                    '2.05.20' => '/gsc/pkg/bio/novocraft/novocraft-2.05.20',
                    '2.05.32' => '/gsc/pkg/bio/novocraft/novocraft-2.05.33',
                    'novocraft'   => 'novoalign',
                );

sub available_novocraft_versions {
    my $self = shift;
    return keys %NOVOCRAFT_VERSIONS;
}

sub path_for_novocraft_version {
    my $class = shift;
    my $version = shift;

    if (defined $NOVOCRAFT_VERSIONS{$version}) {
        return $NOVOCRAFT_VERSIONS{$version};
    }
    die('No path for novocraft version '. $version);
}

sub default_novocraft_version {
    die "default novocraft version: $DEFAULT_VERSION is not valid" unless $NOVOCRAFT_VERSIONS{$DEFAULT_VERSION};
    return $DEFAULT_VERSION;
}

1;

