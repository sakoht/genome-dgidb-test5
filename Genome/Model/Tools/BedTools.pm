package Genome::Model::Tools::BedTools;

use strict;
use warnings;

use Genome;

my $BEDTOOLS_DEFAULT = '2.6.1';

class Genome::Model::Tools::BedTools {
    is  => 'Command',
    is_abstract => 1,
    has_input => [
        arch_os => {
            calculate => q|
                my $arch_os = `uname -m`;
                chomp($arch_os);
                return $arch_os;
            |
        },
        use_version => {
            is  => 'Version', 
            doc => 'BEDTools version to be used.  default_value='. $BEDTOOLS_DEFAULT,
            is_optional   => 1, 
            default_value => $BEDTOOLS_DEFAULT,
        },
    ],
};


sub help_brief {
    "Tools to run BedTools.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
gmt bed-tools ...    
EOS
}

sub help_detail {                           
    return <<EOS 
More information about the BedTools suite of tools can be found at http://code.google.com/p/bedtools/.
EOS
}

my %BEDTOOLS_VERSIONS = (
    '2.6.1' => '/gsc/pkg/bio/bedtools/BEDTools-2.6.1',
    '2.5.4' => '/gsc/pkg/bio/bedtools/BEDTools-2.5.4',
    '2.3.2' => '/gsc/pkg/bio/bedtools/BEDTools-2.3.2',
);

sub path_for_bedtools_version {
    my ($class, $version) = @_;
    $version ||= $BEDTOOLS_DEFAULT;
    my $path = $BEDTOOLS_VERSIONS{$version};
    if ($class->arch_os =~ /64/) {
        if ($path) {
            $path .= '-64';
        }
    }
    return $path if (defined $path && -d $path);
    die 'No path found for samtools version: '. $version;
}

sub default_bedtools_version {
    die "default bedtools version: $BEDTOOLS_DEFAULT is not valid" unless $BEDTOOLS_VERSIONS{$BEDTOOLS_DEFAULT};
    return $BEDTOOLS_DEFAULT;
}

sub bedtools_path {
    my $self = shift;
    return $self->path_for_bedtools_version($self->use_version);
}



1;

