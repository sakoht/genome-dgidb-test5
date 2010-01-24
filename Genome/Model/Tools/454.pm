package Genome::Model::Tools::454;

use strict;
use warnings;

use Genome;
use Data::Dumper;
use File::Temp;

class Genome::Model::Tools::454 {
    is  => ['Command'],
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
            is  => 'string',
            doc => 'version of 454 application to use',
        },
        _tmp_dir => {
            is  => 'string',
            doc => 'a temporary directory for storing files',
        },
        version_subdirectory => {
            is  => 'string',
            doc => '454 subdirectory name',
        },
        test_link => {
            is  => 'string',
            doc => 'link names to default 454 versions',
        },
    ]
};

sub help_brief {
    "tools to work with 454 reads";
}

sub help_detail {
    return <<EOS

EOS
}

sub create {
    my $class = shift;
    my $self  = $class->SUPER::create(@_);
    return unless $self;

    my $link;

    #FOR TEST DATA .. GETS EITHER installed or newbler
    if ( $self->test_link ) {
        $link = $self->test_link;
    }

    #FOR ACTUAL RUNS .. GETS EITHER offIns or mapasm
    elsif ( $self->version_subdirectory ) {
        $link = $self->version_subdirectory;
    }

    #FOR REFERENCE ALIGNEMNT TESTS
    else {
        $link = 'installed';
    }

    unless ( $self->arch_os =~ /64/ ) {
        $self->error_message(
            'All 454 tools must be run from 64-bit architecture');
        return;
    }

    my $tempdir = File::Temp::tempdir( CLEANUP => 1 );
    $self->_tmp_dir($tempdir);
    unless ( $self->version ) {

        #	my $base_path = $self->resolve_454_path .'installed';
        my $base_path = $self->resolve_454_path . $link;
        if ( -l $base_path ) {
            my $link_path = readlink($base_path);
            if ( $link_path =~ /^offInstrumentApps/ ) {
                unless (
                    $link_path =~ /(offInstrumentApps)-(\d\.\d\.\d{2}\.\d{2})/ )
                {
                    $self->error_message(
                        'Link to 454 tools was malformed: ' . $link_path );
                    return;
                }
                $self->version($2);
                $self->version_subdirectory($1);
            }
            elsif ( $link_path =~ /^DataAnalysis/ ) {
                if ($link_path =~ /^(DataAnalysis-([\d\.]+))/) {
                    $self->version_subdirectory($1);
                    $self->version($2);
                }
                else {
                    $self->error_message(
                        'Link to 454 tools was malformed: ' . $link_path );
                    return;
                }
                # REMOVE THIS WHEN WE ACTUALLY SUPPORT THE NEW DIRECTORY STRUCTURE
                die "The DatanAnalysis* directory structure for newbler is not supported yet!  Contact Informatics." 
            }
            elsif ( $link_path =~ /^mapasm454_source/ ) {
                unless ( $link_path =~ /(mapasm454_source)_(\d{8})/ ) {
                    $self->error_message(
                        'Link to 454 tools was malformed: ' . $link_path );
                    return;
                }
                $self->version($2);
                $self->version_subdirectory($1);
            }
            else {
                $self->error_message("Cannot resolve version!; Link path (from $base_path) does not match expected offInstrumentApps or mapasm454_source patterns!!: $link_path");
                return;
            }
        }
        else {
            $self->error_message('Expected symlink to installed software');
            return;
        }
    }
    unless ( $self->version ) {
        $self->error_message(
            'Failed to resolve version number of 454 applications');
        return;
    }
    return $self;
}

sub resolve_454_path {
    return '/gsc/pkg/bio/454/';
}

sub resolve_app_bin_name {
    my $self = shift;
    my $app_bin_name;
    $app_bin_name = 'bin'
      if $self->version_subdirectory eq 'offInstrumentApps';
    $app_bin_name = 'applicationsBin'
      if $self->version_subdirectory eq 'mapasm454_source';
    return $app_bin_name;
}

sub bin_path {
    my $self = shift;
    my $bin_path;

    #difference is - vs _;
    if ( $self->version_subdirectory eq 'offInstrumentApps' ) {
        $bin_path =
            $self->resolve_454_path
          . $self->version_subdirectory . '-'
          . $self->version . '/'
          . $self->resolve_app_bin_name;
    }
    elsif ( $self->version_subdirectory eq 'mapasm454_source' ) {
        $bin_path =
            $self->resolve_454_path
          . $self->version_subdirectory . '_'
          . $self->version . '/'
          . $self->resolve_app_bin_name;
    }
    return $bin_path;
}

1;

