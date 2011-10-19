package Genome::Site;

use strict;
use warnings;

our $VERSION = $Genome::VERSION;

BEGIN {

    our %DEFAULT_ENV = (
        GENOME_SYS_SERVICES_MEMCACHE => 'localhost:11211',
        GENOME_SYS_SERVICES_SOLR => 'localhost:8005/solr',
    );

    for my $var (keys %DEFAULT_ENV) {
        if (not exists $ENV{$var}) {
            $ENV{$var} = $DEFAULT_ENV{$var};
        }
    }

    if (my $config = $ENV{GENOME_CONFIG}) {
        # call the specified configuration module;
        eval "use $config";
        die $@ if $@;
    }
    else {
        # look for a config module matching all or part of the hostname 
        use Sys::Hostname;
        my $hostname = Sys::Hostname::hostname();
        my @hwords = reverse split('\.',$hostname);
        while (@hwords) {
            my $pkg = 'Genome::Site::' . join("::",@hwords);
            local $SIG{__DIE__};
            local $SIG{__WARN__};
            eval "use $pkg";
            if ($@) {
                pop @hwords;
                next;
            }
            else {
                last;
            }
        }
    }
}

# This module potentially conflicts to the perl-supplied Config.pm if you've
# set up your @INC or -I options incorrectly.  For example, you used -I /path/to/modules/Genome/
# instead of -I /path/to/modules/.  Many modules use the real Config.pm to get info and
# you'll get wierd failures if it loads this module instead of the right one.
{
    my @caller_info = caller(0);
    if ($caller_info[3] eq '(eval)' and $caller_info[6] eq 'Config.pm') {
        die "package Genome::Config was loaded from a 'use Config' statement, and is not want you wanted.  Are your \@INC and -I options correct?";
    }
}

1;

=pod

=head1 NAME

Genome::Site - hostname oriented site-based configuration

=head1 DESCRIPTION

Use the fully-qualified hostname to look up site-based configuration.

=head1 AUTHORS

This software is developed by the analysis and engineering teams at 
The Genome Center at Washington Univiersity in St. Louis, with funding from 
the National Human Genome Research Institute.

=head1 LICENSE

This software is copyright Washington University in St. Louis.  It is released under
the Lesser GNU Public License (LGPL) version 3.  See the associated LICENSE file in
this distribution.

=head1 BUGS

For defects with any software in the genome namespace,
contact genome-dev@genome.wustl.edu.

=cut

