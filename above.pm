
package above;

use strict;
use warnings;

sub import {
    my $package = shift;
    for (@_) {
        use_package($_);
    }
}

sub use_package {
    my $class = shift;

    my $module = $class;
    $module =~ s/::/\//g;
    $module .= ".pm";

    require Cwd;
    my $cwd = Cwd::cwd();
    my @parts = ($cwd =~ /\//g);
    my $dirs_above = scalar(@parts);
    my $path=$cwd.'/';
    until (-e "$path./$module") {
        if ($dirs_above == 0) {
            # Not found.  Use the one out under test.
            # When deployed.
            $path = "";
            last;
        };
        #print "Didn't find it in $path, trying higher\n";
        $path .= "../";
        $dirs_above--;
    }

    # Get the special path in place
    if (length($path)) {
        while ($path =~ s:/[^/]+/\.\./:/:) { 1 } # simplify
        print STDERR "Using libraries at $path\n";
        eval "use lib '$path';";
        die $@ if $@;
    }

    # Temporary hack until the UR modules are deployed
    # This must be present until the UR modules are deployed lab-wide.
    unless (grep { /ur-dev/ } @INC) {
        my $ur_path = $ENV{UR_PATH} || '/gsc/scripts/test/ur-dev';
        eval "use lib '$ur_path';";
        die $@ if $@;
    }

    # Now use the module.
    eval "use $class";
    die $@ if $@;

};

1;

=pod

=head1 NAME

use above

=head1 SYNOPSIS

use above "My::Module";

=head1 DESCRIPTION

Uses a module as though the cwd and each of its parent directories were at the beginnig of @INC.
Used by the command-line wrappers for Command modules.

=head1 BUGS

Report bugs to software@watson.wustl.edu

=head1 AUTHOR

Scott Smith

ssmith@watson.wustl.edu

=cut

