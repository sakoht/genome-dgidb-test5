package Genome::Site::WUGC;
use strict;
use warnings;

BEGIN {
    if ($ENV{GENOME_DEV_MODE}) {
        $ENV{GENOME_SYS_SERVICES_MEMCACHE} ||= 'apipe-dev.gsc.wustl.edu:11211';
        $ENV{GENOME_SYS_SERVICES_SOLR} ||= 'http://solr-dev:8080/solr';
    }
    else {
        $ENV{GENOME_SYS_SERVICES_MEMCACHE} ||= 'imp.gsc.wustl.edu:11211';
        $ENV{GENOME_SYS_SERVICES_SOLR} ||= 'http://solr:8080/solr';
    }
}

# this conflicts with all sorts of Finishing/Finfo stuff
# ironicall it is used by Pcap stuff
BEGIN { $INC{"UNIVERSAL/can.pm"} = 'no' };
BEGIN { $INC{"UNIVERSAL/isa.pm"} = 'no' };

# this keeps available parts of the UR pre-0.01 API we still use
use UR::ObjectV001removed;

# ensure nothing loads the old Genome::Config module
BEGIN { $INC{"Genome/Config.pm"} = 'no' };

# we removed UR::Time, but lots of things still depend on it
# this brings back UR::Time as a namespace, but only or legacy things
use Genome::Site::WUGC::LegacyTime;
BEGIN { $INC{ "UR/Time.pm"} = "no" };

# bring in the regular Genome::Sys, then extend
use Genome::Sys;
use Genome::Site::WUGC::SysUnreleased;      # extensions to Genome::Sys

# the old Genome::Config is all deprecated
# the core stuff about looking up your host config is now in Genome::Site
use Genome::Site::WUGC::LegacyConfig;   

# set our internal paths for data and software
$ENV{GENOME_DB} ||= '/gsc/scripts/opt/genome/db';
$ENV{GENOME_SW} ||= '/gsc/pkg/bio';

# testsuite data
$ENV{GENOME_TESTSUITE_INPUTS_PATH} = '/gsc/var/cache/testsuite/data';

# configure our local ensembl db
$ENV{GENOME_DB_ENSEMBL_API_PATH} ||= '/gsc/scripts/share/ensembl-64';
$ENV{GENOME_DB_ENSEMBL_HOST} ||= 'mysql1';
$ENV{GENOME_DB_ENSEMBL_USER} ||= 'mse';
$ENV{GENOME_DB_ENSEMBL_PORT} ||= '3306';

# configuration for internal WUGC network software & LIMS 
# this module is called by Genome::Config::edu::wustl::gsc right now on all *.gsc.wustl.edu hosts
# print STDERR "using " . __PACKAGE__ . "\n";

# ensure we can get to legacy modules 
use Class::Autouse;
Class::Autouse->autouse(qr/Finfo.*/);
Class::Autouse->autouse(qr/Bio.*/);

# Loads site-specific observers
use Genome::Site::WUGC::Observers;

# this callback will load the GSCApp module, and initialize the app to work with GSC modules
my $initialized = ''; 
our $checks = 0;
my $callback = sub {
    my ($pkg, $method, $class) = @_;
    $checks++;
    # print "ck @_: $initialized\n";

    return if $initialized eq 'complete' or $initialized eq 'in progress';
    return unless substr($pkg,0,5) eq 'GSC::' or substr($pkg,0,5) eq 'App::';

    if ($^X eq '/usr/bin/perl') {  # only when using the LIMS interpreter is this okay 
        Carp::confess("Attempt to use $class on the local /usr/bin/perl interpreter!  GSC::* and App::* modules must be used with the LIMS interpreter.  Contact APIPE for support!");
    }

    # load and initialize GSCApp the first time something GSC:: or App:: is used.
    # since App::Init configures its own dynamic loader we dont' do anything 
    # afterward, but we do need to wrap its configuration the first time to prevent conflicts

    warn "using internal LIMS modules...";

    if ($GSCApp::{BEGIN}) {
        # We've already done "use GSCApp" somewhere, and it was not
        # done before "use Genome".  Just bail.
        $initialized = 'error';
        Carp::confess("Some code in the Genome tree has a 'use GSCApp' in it.  Please remove this.");
    }

    if ($initialized eq 'error') {
        # the above happened earlier, and apparently the app did not exit
        Carp::confess("Cannot work with $pkg.  Some code in the Genome tree has a 'use GSCApp' in it.  Please remove this.");
    }

    $initialized = 'in progress';

    # remove the placeholder from above so we can actually load this module
    delete $INC{"App/Init.pm"};
    delete $INC{"GSCApp.pm"};
    
    require GSCApp;
    GSCApp->import();

    # ensure our access to the GSC schema is rw, and that our special env variables match up
    unless (App::Init->initialized) {
        App::DB->db_access_level('rw');
    }
    _sync_env();

    # GSCApp removes our overrides to can/isa for Class::Autoloader.  Tell it to put them back.
    App::Init->_restore_isa_can_hooks();

    # call the init process to prepare the object cache if it needs being created.
    App->init;

    $initialized = 'complete';

    return $class->can($method);
};

if ($GSCApp::{BEGIN}) {
    # GSCApp is was used first.
    
    # configure Genome & UR to follow its configuration.
    _sync_env();

    # GSCApp removes our overrides to can/isa for Class::Autoloader.  Tell it to put them back.
    App::Init->_restore_isa_can_hooks();
}
else {
    # No code has used GSCApp yet.
    Class::Autouse->sugar($callback);

    # The following ensures that, if someone uses GSCApp directly later, instead
    # of using the GSC classes directly, the callback will catch it and raise an error.
    # Since App::Init messes with UNIVERSAL::{can,isa} directly we need to 
    # wrap the actual use of this module and restore those methods.
    $INC{"App/Init.pm"} ||= 'virtual';
    $INC{"GSCApp.pm"} ||= 'virtual';
}

sub _sync_env {
    if (App::DB::TableRow->use_dummy_autogenerated_ids || UR::DataSource->use_dummy_autogenerated_ids) {
        unless (App::Init->initialized) {
            App::DB::TableRow->use_dummy_autogenerated_ids(1);
        }
        UR::DataSource->use_dummy_autogenerated_ids(1);
    }
    if (App::DBI->no_commit || UR::DBI->no_commit) {
        unless (App::Init->initialized) {
            App::DBI->no_commit(1);
        }
        UR::DBI->no_commit(1);
    }
}


1;

=pod

=head1 NAME

Genome::Site::WUGC - internal configuration for the WU Institute of Genomic Medicine 

=head1 DESCRIPTION 

Configures the Genome Modeling system to work on the internal network at 
The Institute of Genomic Medicine at Washington University

This module ensures that GSCApp and related modules are avialable to the running application.

It is currently a goal that GSCApp need not be used by this module, and that individual
modules under it provide transparent wrappers for WUIGM-specific infrastructure.

=head1 BUGS

For defects with any software in the genome namespace,
contact software@genome.wustl.edu.

=head1 SEE ALSO

B<Genome>, B<Genome::Config>, B<Genome::Site>

=cut



