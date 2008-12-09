package Genome::Model::Tools::454;

use strict;
use warnings;

use Genome;
use Data::Dumper;
use File::Temp;

class Genome::Model::Tools::454 {
    is => ['Command'],
    has => [
            arch_os => {
                        calculate => q|
                            my $arch_os = `uname -m`;
                            chomp($arch_os);
                            return $arch_os;
                        |
                    },
	    assembler_version => {
		                  is    => 'string',
			          doc   => 'version of 454 application to use',
				  is_optional => 1,
	                         },

        ],
    has_optional => [
                     _tmp_dir => {
                                  is => 'string',
                                  doc => 'a temporary directory for storing files',
                              }
                 ]
};

sub help_brief {
    "tools to work with 454 reads"
}

sub help_detail {                           # This is what the user will see with --help <---
    return <<EOS

EOS
}

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    my $tempdir = File::Temp::tempdir(CLEANUP => 1);
    $self->_tmp_dir($tempdir);
    return $self;
}

sub bin_path {
    my $self = shift;

    my $base_path = '/gsc/pkg/bio/454/';
    
    if ($self->assembler_version) {
	$base_path = '/gsc/pkg/bio/454/offInstrumentApps-'.$self->assembler_version;
    }
    else {
	$base_path .= 'installed';
    }

    my $tail;
    if ($self->arch_os =~ /64/) {
        $tail = '-64/bin';
    }
    else {
        $tail = '/bin';
    }

    return $base_path . $tail;
}

1;

