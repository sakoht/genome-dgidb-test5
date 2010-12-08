package Genome::Model::Tools::Varscan;

use strict;
use warnings;

use Genome;
use Data::Dumper;
use File::Temp;

my $DEFAULT_VERSION = '2.2.4';

class Genome::Model::Tools::Varscan {
    is => ['Command'],
    has_optional => [
         version => {
             is    => 'String',
             doc   => 'version of Varscan application to use',
         },
    ],
};

sub help_brief {
    "tools to work with Varscan output"
}

sub help_detail {                           # This is what the user will see with --help <---
    return <<EOS

EOS
}

my %VARSCAN_VERSIONS = (
    '2.2.4' => '/gsc/scripts/lib/java/VarScan/VarScan.v2.2.4.jar',
);

sub path_for_version {
    my $class = shift;
    my $version = shift || $DEFAULT_VERSION;

    if($version eq 'latest') {
        return $class->path_for_latest_version;
    }

    unless(exists $VARSCAN_VERSIONS{$version}) {
        $class->error_message('No path found for VarScan Version ' . $version);
        die $class->error_message;
    }

    return $VARSCAN_VERSIONS{$version};
}

sub path_for_latest_version {
    my $class = shift;
    my $link = '/gsc/scripts/lib/java/VarScan/VarScan.jar';

    unless(-e $link and -l $link) {
        $class->error_message('Link to latest version not found or not a link!');
    }

    return $link;
}

sub default_version {
    my $class = shift;

    unless(exists $VARSCAN_VERSIONS{$DEFAULT_VERSION}) {
        $class->error_message('Default VarScan version (' . $DEFAULT_VERSION . ') is invalid.');
        die $class->error_message;
    }

    return $DEFAULT_VERSION;
}

1;

