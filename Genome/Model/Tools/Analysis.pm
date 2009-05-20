package Genome::Model::Tools::Analysis;

use strict;
use warnings;

use Genome;
use Data::Dumper;
use File::Temp;

class Genome::Model::Tools::Analysis {
    is => ['Command'],
    has => [
            arch_os => {
                        calculate => q|
                            my $arch_os = `uname -m`;
                            chomp($arch_os);
                            return $arch_os;
                        |
                    },
        ],
    has_optional => [
                     version => {
                                 is    => 'string',
                                 doc   => 'version of Analysis application to use',
                             },
                     _tmp_dir => {
                                  is => 'string',
                                  doc => 'a temporary directory for storing files',
                              },
                 ]
};

sub help_brief {
    "tools to work with Analysis output"
}

sub help_detail {                           # This is what the user will see with --help <---
    return <<EOS

EOS
}

sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);

    unless ($self->arch_os =~ /64/) {
        $self->error_message('Most Analysis tools must be run from 64-bit architecture');
        return;
    }
    my $tempdir = File::Temp::tempdir(CLEANUP => 1);
    $self->_tmp_dir($tempdir);

    return $self;
}



1;

