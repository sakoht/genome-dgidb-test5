package Genome::Model::Tools::Allpaths::Base;

use strict;
use warnings;

use Genome;

my %versions = (
    39099 => { version_path => "allpathslg-39099/bin",
               prepare_path => "allpaths_cache"},
    36892 => { version_path => "allpathslg-36892/bin",
               prepare_path => ""},
);

class Genome::Model::Tools::Allpaths::Base {
    is => 'Command::V2',
    is_abstract => 1,
    has => [
	    version => {
            is => 'Text',
            doc => 'Version of ALLPATHS to use',
#            valid_values => [ sort keys %versions ],
            default_value => "36892",
        },
    ],
};

sub allpaths_directory {
    return '/gsc/pkg/bio/allpaths';
}

sub allpaths_version_directory {
    my ($self, $version) = @_;
    return $self->allpaths_directory."/".$versions{$version}->{"version_path"};
}

sub allpaths_prepare_directory {
    my ($self, $version) = @_;
    return $self->allpaths_version_directory($version)."/".$versions{$version}->{"prepare_path"};
}

sub RunAllPathsLG_path {
}

1;

