package Genome::Model::Tools::Rtg;

use strict;
use warnings;

use Genome;
use File::Basename;

my $DEFAULT = 'EAP-2010-08-03-30243';

class Genome::Model::Tools::Rtg {
    is => 'Command',
    has => [
        use_version => { is => 'Version', is_optional => 1, default_value => $DEFAULT, doc => "Version of rtg to use, default is $DEFAULT" },
    ],
};

sub sub_command_sort_position { 12 }

sub help_brief {
    "Tools to run RTG.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools rtg...    
EOS
}

sub help_detail {                           
    return <<EOS 
~rtg/rtg/README.txt
EOS
}


my %RTG_VERSIONS = (
	'v2.0.1-build-28762' => '/gsc/bin',
	'EAP-2010-08-03-30243' => '/gsc/pkg/bio/rtg/rtg-EAP-2010-08-03-30243',
        'rtg'   => 'rtg',
);


sub rtg_path {
    my $self = $_[0];
    return $self->path_for_rtg_version($self->use_version);
}

sub available_rtg_versions {
    my $self = shift;
    return keys %RTG_VERSIONS;
}

sub path_for_rtg_version {
    my $class = shift;
    my $version = shift || $DEFAULT;

    if (defined $RTG_VERSIONS{$version}) {
        return $RTG_VERSIONS{$version};
    }
    
    die('No path for rtg version '. $version);
}

sub path_for_rtg_format {
    my ($self,$version) = @_;

    if (defined $RTG_VERSIONS{$version}) {
        return $self->path_for_rtg_version . '/rtg format';
    }
 
    die('No path for rtg version '. $version);
}

sub path_for_rtg_sdfsplit {
    my ($self,$version) = @_;

    if (defined $RTG_VERSIONS{$version}) {
        return $self->path_for_rtg_version . '/rtg sdfsplit';
    }
 
    die('No path for rtg version '. $version);
}

sub path_for_rtg_map {
    my ($self,$version) = @_;

    if (defined $RTG_VERSIONS{$version}) {
        return $self->path_for_rtg_version . '/rtg map';
    }
 
    die('No path for rtg version '. $version);
}

sub path_for_rtg_mapx {
    my ($self,$version) = @_;

    if (defined $RTG_VERSIONS{$version}) {
        return $self->path_for_rtg_version . '/rtg mapx';
    }
 
    die('No path for rtg version '. $version);
}

sub default_rtg_version {
    die "default samtools version: $DEFAULT is not valid" unless $RTG_VERSIONS{$DEFAULT};
    return $DEFAULT;
}
        

1;

