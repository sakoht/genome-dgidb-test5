package Genome::Model::Tools::Mummer;

use strict;
use warnings;

use Genome;

my $DEFAULT = '3.22-64';

class Genome::Model::Tools::Mummer{
    is => 'Command',
    has => [
        use_version => {
            is => 'Text',
            is_optional => 1,
            default_value => $DEFAULT,
            doc => "Version of nucmer to use, default is $DEFAULT",
        },
    ],
};

sub help_brief {
}

sub help_detail {
    return <<EOS
EOS
}

my %VERSIONS = (
    '3.15'    => '/gsc/pkg/bio/mummer/MUMmer3.15',
    '3.20'    => '/gsc/pkg/bio/mummer/MUMmer3.20',
    '3.21'    => '/gsc/pkg/bio/mummer/MUMmer3.21',
    '3.22'    => '/gsc/pkg/bio/mummer/MUMmer3.22',
    '3.22-64' => '/gsc/pkg/bio/mummer/MUMmer3.22-64',
);

sub path_for_version {
    my $self = shift;
    my $version = $self->use_version;
    die ("No path for version: $version") if not exists $VERSIONS{$version};
    return $VERSIONS{$version};
}

sub path {
    return $_[0]->path_for_version( $_[0]->use_version );
}

sub available_versions {
    return keys %VERSIONS;
}

1;
