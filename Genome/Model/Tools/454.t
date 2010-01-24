#!/gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

use Test::More skip_all => "The new installed version of newbler has a new directory name/structure.  Update me to work with it!";

BEGIN {
    my $archos = `uname -a`;
    if ( $archos !~ /64/ ) {
        plan skip_all => "Must run from 64-bit machine";
    }
    plan tests => 11;
    use_ok('Genome::Model::Tools::454');
}

my $arch_os = `uname -m`;
chomp($arch_os);

my @installed_links = qw/ installed newbler /;
foreach my $link (@installed_links) {
    my $path           = '/gsc/pkg/bio/454/';
    my $installed_link = $path . $link;
    my $installed_path = readlink($installed_link);
    my $tool_454 = Genome::Model::Tools::454->create( test_link => $link );
    isa_ok( $tool_454, 'Genome::Model::Tools::454' )
        or diag(Genome::Model::Tools::454->error_message());
    is( $tool_454->arch_os, $arch_os, 'arch_os' );
    my $app_bin_name;
    if ( $link =~ /installed/ ) {
        like( $tool_454->version, '/\d\.\d.\d{2}.\d{2}/',
            'found a version like 0.0.00.00' );
        $app_bin_name = '/bin';
    }
    if ( $link =~ /newbler/ ) {
        like( $tool_454->version, '/\d{8}/', 'found a version like 00000000' );
        $app_bin_name = '/applicationsBin';
    }
    ok( -d $tool_454->bin_path, 'bin directory exists' );
    my $installed_bin =
      $tool_454->resolve_454_path . $installed_path . $app_bin_name;
    is( $tool_454->bin_path, $installed_bin,
        'expected path found for bin directory' );
}

