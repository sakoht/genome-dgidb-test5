package Genome::Model::Tools::ViromeScreening;

use strict;
use warnings;

use Genome;
use Command;
use Workflow::Simple;
use Data::Dumper;
use File::Basename;


UR::Object::Type->define(
    class_name => __PACKAGE__,
    is         => 'Command',
    has        => [

            fasta_file => {
                           doc => 'file of reads to be checked for contamination',
                           is => 'String',
                           is_input => 1,
                       },
            barcode_file => { 
                           doc => 'list of samples for screening',
                           is => 'String',
                           is_input => 1,
                       },
            dir     => {
                           doc => 'directory of inputs',
                           is => 'String',
		           is_optional => 1,
		           default => $ENV{"PWD"},

                        },
            logfile => {
                            doc => 'output file for monitoring progress of pipeline',
                            is => 'String',
		            is_optional => 1,
                            default => "logfile.txt",
                        },
    ]
);

sub help_brief {
    "Runs virome screening workflow";
}

sub help_synopsis {
    return <<"EOS"
    genome-model tools virome-screening ... 
EOS
}

sub help_detail {
    return <<"EOS"
    Runs the virome screening pipeline, using ViromeEvent modules.  Takes directory path, fasta, sample log, and logfile. 
EOS
}

sub execute {
    my $self = shift;
    unlink($self->logfile) if (-e $self->logfile);
    my $output = run_workflow_lsf(
                              '/gsc/var/cache/testsuite/data/Genome-Model-Tools-ViromeScreening/virome-screening2.xml',
                              'fasta_file'  => $self->fasta_file,
                              'barcode_file'=> $self->barcode_file,
                              'dir'         => $self->dir,
                              'logfile'     => $self->logfile,
                          );
    my $mail_dest = $ENV{USER}.'@genome.wustl.edu';
    my $sender = Mail::Sender->new({
        smtp => 'gscsmtp.wustl.edu',
        from => 'virome-screen@genome.wustl.edu',
        replyto => 'virome-screen@genome.wustl.edu',
    });
    $sender->MailMsg({
        to => $mail_dest,
        subject => "Virome Screen completed",
        msg     => "Virome Screen completed for gmt virome-screening\n" .
                   "\t--barcode-file=" . $self->barcode_file . " --fasta-file=" . $self->fasta_file . " --dir=" . $self->dir . " --logfile=" . $self->logfile,
    });
    return 1;
}

