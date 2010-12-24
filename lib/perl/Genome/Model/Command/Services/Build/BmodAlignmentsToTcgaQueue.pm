package Genome::Model::Command::Services::Build::BmodAlignmentsToTcgaQueue;

use strict;
use warnings;

use Genome;

require Carp;
use Data::Dumper 'Dumper';

class Genome::Model::Command::Services::Build::BmodAlignmentsToTcgaQueue { 
    is => 'Genome::Command::Base',
    has => [
        builds => {
            is => 'Genome::Model::Build',
            shell_args_position => 1,
            is_many => 1,
            doc => 'Builds to modify the queue of PEND alignment jobs.',
        },
    ],
};

sub execute {
    my $self = shift;

    my @builds = $self->builds;
    if ( not @builds ) {
        $self->error_message('No builds to modify');
    }

    for my $build ( @builds ) {
        my $status = $build->status;
        if ( $status ne 'Running' ) {
            $self->error_message('Build ('.$build->id.') is not running');
        }
        $self->_bmod_align_reads_instances_for_build($build);
    }

    return 1;
}

sub _bmod_align_reads_instances_for_build {
    my ($self, $build)  = @_;

    Carp::confess('No build') if not $build;

    $self->status_message('Build: '.$build->id);

    my $wf = $build->newest_workflow_instance;
    if ( not $wf ) {
        $self->error_message('Build ('.$build->id.') does not have a workflow instance');
        return;
    }
    if ( not $wf->is_running ) {
        $self->error_message('Build ('.$build->id.') does not have a running workflow instance');
        return;
    }

    my @alignment_instances = grep { $_->name =~ / alignment$/ } $wf->ordered_child_instances;
    if ( not @alignment_instances ) {
        $self->error_message('Build\'s ('.$build->id.') workflow does not have any alignment instances');
        return;
    }
    if ( @alignment_instances > 1 ) {
        $self->error_message('Build\'s ('.$build->id.') workflow has more than one alignment instances');
        return;
    }
    if ( not $alignment_instances[0]->is_running ) {
        $self->error_message('Build ('.$build->id.') does not have a running alignment instance');
        return;
    }

    my @align_reads_instances = grep { $_->name =~ /^align-reads / } $alignment_instances[0]->ordered_child_instances;
    if ( not @align_reads_instances ) {
        $self->error_message('Build\'s ('.$build->id.') alignemnt instance does not have any align_reads instances');
        return;
    }

    for my $align_reads_instance ( @align_reads_instances ) {
        next if not $align_reads_instance->is_running;
        my $lsf_job_id = $align_reads_instance->current->dispatch_identifier;
        my $cmd = "bmod -q tcga -m blade64 $lsf_job_id";
        #print "$cmd\n"; next;
        my $rv = eval{ Genome::Utility::FileSystem->shellcmd(cmd => $cmd); };
    }

    return 1;
}

1;

=pod

=head1 Disclaimer

Copyright (C) 2005 - 2009 Genome Center at Washington University in St. Louis

This module is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=head1 Author(s)

B<Eddie Belter> I<ebelter@genome.wustl.edu>

=cut

#$HeadURL$
#$Id$

