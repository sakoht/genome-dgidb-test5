package Genome::Model::Tools::Mosaik;

use strict;
use warnings;

use Genome;
use File::Basename;


#declare a default version here
##########################################
my $DEFAULT = '1.0.1388';

class Genome::Model::Tools::Mosaik {
    is => 'Command',
    has => [
        use_version => { is => 'Version', is_optional => 1, default_value => $DEFAULT, doc => "Version of Mosaik to use, default is $DEFAULT" },
    ],
};

sub sub_command_sort_position { 12 }

sub help_brief {
    "Tools to run Mosaik or work with its output files.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools mosaik ...    
EOS
}

sub help_detail {                           
    return <<EOS 
EOS
}


my %MOSAIK_VERSIONS = (
	'1.0.1388' => '/gscmnt/sata820/info/medseq/alignment-test/mosaik_x64/bin/Mosaik',
    'mosaik'   => 'Mosaik',
);


sub mosaik_path {
    my $self = $_[0];
    return $self->path_for_mosaik_version($self->use_version);
}

sub available_mosaik_versions {
    my $self = shift;
    return keys %MOSAIK_VERSIONS;
}

sub path_for_mosaik_version {
    my $class = shift;
    my $version = shift;

    if (defined $MOSAIK_VERSIONS{$version}) {
        return $MOSAIK_VERSIONS{$version};
    }
    die('No path for Mosaik version '. $version);
}

sub default_mosaik_version {
    die "default samtools version: $DEFAULT is not valid" unless $MOSAIK_VERSIONS{$DEFAULT};
    return $DEFAULT;
}
        

1;

