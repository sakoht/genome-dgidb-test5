package Genome;

use warnings;
use strict;

# software infrastructure
use UR;

# this keeps available parts of the UR pre-0.01 API we still use
use UR::ObjectV001removed;

# environmental configuration
use Genome::Config;

# linkage to certain GC LIMS classes
use GSCApp;

# account for a perl bug in pre-5.10 by applying a runtime patch to Carp::Heavy
use Carp;
use Carp::Heavy;

BEGIN {
    no warnings 'redefine';
    use Sys::Hostname;
    *Command::status_message_orig = \&Command::status_message;
    *Command::status_message = sub { 
        my $self = shift; 
        my $hostname = hostname;
        $hostname =~s/\.gsc\.wustl\.edu//;
        my $time = UR::Time->now_local;
        my $prefix = "($hostname) [$time]";
        $self->status_message_orig("$prefix -- " . shift)
    };
    *UR::ModuleBase::status_message_orig = \&UR::ModuleBase::status_message;
    *UR::ModuleBase::status_message = sub { 
        my $self = shift; 
        my $hostname = hostname;
        $hostname =~s/\.gsc\.wustl\.edu//;
        my $time = UR::Time->now_local;
        my $prefix = "($hostname) [$time]";
        $self->status_message_orig("$prefix -- " . shift)
    };
}

if ($] < 5.01) {
    no warnings;
    *Carp::caller_info = sub {
        package Carp;
        our $MaxArgNums;
        my $i = shift(@_) + 1;
        package DB;
        my %call_info;
        @call_info{
            qw(pack file line sub has_args wantarray evaltext is_require)
        } = caller($i);

        unless (defined $call_info{pack}) {
            return ();
        }

        my $sub_name = Carp::get_subname(\%call_info);
        if ($call_info{has_args}) {
            # SEE IF WE CAN GET AROUND THE BIZARRE ARRAY COPY ERROR...
            my @args = ();
            if ($MaxArgNums and @args > $MaxArgNums) { # More than we want to show?
                $#args = $MaxArgNums;
                push @args, '...';
            }
            # Push the args onto the subroutine
            $sub_name .= '(' . join (', ', @args) . ')';
        }
        $call_info{sub_name} = $sub_name;
        return wantarray() ? %call_info : \%call_info;
    };
    use warnings;

}

# ensure our access to the GSC schema is rw, and that our special env variables match up
unless (App::Init->initialized) {
    App::DB->db_access_level('rw');
}
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

# GSCApp removes our overrides to can/isa for Class::Autoloader.  Tell it to put them back.
App::Init->_restore_isa_can_hooks();

# this ensures that the search system is updated when certain classes are updated 
Genome::Search->register_callbacks('UR::Object');

# DB::single is set to this value in many places, creating a source-embedded break-point
# set it to zero in the debugger to turn off the constant stopping...
$DB::stopper = 1;

# the standard namespace declaration for a UR namespace
UR::Object::Type->define(
    class_name => 'Genome',
    is => ['UR::Namespace'],
    english_name => 'genome',
);

1;

=pod

=head1 NAME

Genome - the namespace for genome analysis and modeling 

=head1 SYNOPSIS

use Genome;

# modules in the genome namespace will now dynomically load

 $m = Genome::Model->get(...);

# modules in the GSC namespace will also load

 $r = GSC::RunLaneSolexa->get(...);

=head1 BUGS

For defects with any software in the genome namespace,
contact software@genome.wustl.edu.

=head1 SEE ALSO

B<Genome::Model>, B<Genome::Model::Tools>

B<Genome::Taxon>, B<Genome::PopulationGroup>, B<Genome::Individual>,
B<Genome::Sample>, B<Genome::Library>, B<Genome::InstrumentData>

=cut

