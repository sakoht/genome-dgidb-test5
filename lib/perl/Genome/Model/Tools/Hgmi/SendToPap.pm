package Genome::Model::Tools::Hgmi::SendToPap;

use strict;
use warnings;

use Genome;
use Command;
use Carp;

use File::Slurp;
use File::Path qw/ mkpath /;
use File::Temp qw/ tempfile tempdir /;
use DateTime;
use List::MoreUtils qw/ uniq /;
use IPC::Run;
use Workflow::Simple;
use Data::Dumper;
use PAP;

use Bio::Seq;
use Bio::SeqIO;

class Genome::Model::Tools::Hgmi::SendToPap (
    is => 'Command',
    has => [
        locus_tag => {
            is  => 'String',
            doc => 'Taxonomy name',
        },
        sequence_set_id => {
            is  => 'Integer',
            doc => 'Sequence set id in MGAP database',
        },
	    sequence_name => {
	        is  => 'String',
	        doc => 'Assembly name in MGAP database',
	    },
	    organism_name => {
	        is  => 'String',
	        doc => 'Organism name in MGAP database',
	    },
        gram_stain => {
            is => 'String',
            doc => 'Gram Stain',
            valid_values => ['positive','negative']
        },
        blastp_archive_dir => {
            is  => 'String',
            doc => 'blastp raw output archive directory',
        },
        interpro_archive_dir => {
            is  => 'String',
            doc => 'Intepro raw output archive directory',
        },
        keggscan_archive_dir => {
            is  => 'String',
            doc => 'keggscan raw output archive directory',
        },
        psortb_archive_dir => {
            is => 'Path',
            doc => 'psortb raw output archive directory',
        },
        pep_file => {
            is => 'String',
            doc => 'Fasta file of gene proteins',
        },
    ],
    has_optional => [
        taxon_id => {
            is  => 'Integer',
            doc => 'NCBI Taxonomy id',
        },
        workflow_xml => {
            is => 'String',
            doc => 'Workflow xml file',
        },
        dev => {
            is => 'Boolean',
            doc => 'Use development databases',
        },
        chunk_size => {
            is => 'Integer',
            doc => 'Chunk size parameter',
            default => 10,
        },
        resume_workflow => { 
            is => 'String',
            doc => 'resume (crashed) workflow from previous invocation',
        },
    ],
);

sub help_brief { return 'Kicks off the protein annotation workflow'; }
sub help_synopsis { return help_brief(); }
sub help_detail {
    return <<EOS
Bridges between HGMI tools and PAP.  This tool loads predictions from mgap to
biosql, pulls data from biosql, then initializes and runs the PAP workflow.
EOS
}

sub execute {
    my $self = shift;

    # Check if each archive directory exists and create it if it doesn't
    for my $archive_path ($self->blastp_archive_dir, $self->interpro_archive_dir, $self->keggscan_archive_dir) {
        unless (-d $archive_path) {
            my $rv = mkpath($archive_path);
            unless ($rv) {
                $self->error_message("Could not make archive directory at $archive_path!");
                croak;
            }
        }
    }

    my $previous_workflow_id = $self->resume_workflow();

    # Start timer here
    my $starttime = DateTime->now(time_zone => 'America/Chicago');
    #unless (defined($previous_workflow_id)) {
    #    $self->status_message("Moving data from mgap to biosql SendToPap.pm");
    #    $self->mgap_to_biosql();

    #    $self->status_message("Creating peptide file SendToPap.pm");
    #    $self->get_gene_peps();
    #}
    
    # interface to workflow to start the PAP.
    $self->do_pap_workflow();

    # end timer, log run time
    my $finishtime = DateTime->now(time_zone => 'America/Chicago');
    my $runtime = ($finishtime->epoch() - $starttime->epoch());
    $self->activity_log($runtime,$self->locus_tag );

    return 1;
}

## need workflow item here...

sub do_pap_workflow {
    my $self = shift;

    my $xml_file = __FILE__ . '.xml';
    my $fasta_file = $self->pep_file;
    my $chunk_size = $self->chunk_size;

    my $previous_workflow_id = $self->resume_workflow();
   
    unless (defined $previous_workflow_id) {
        unless (-f $fasta_file) {
            confess "Could not find fasta file at $fasta_file";
        }
    }

    my $workflow_dev_flag = 0;
    if ($self->dev()) { $workflow_dev_flag = 1; }

    my $output;
    if (defined($previous_workflow_id)) {
        $output = resume_lsf($previous_workflow_id);
    }
    else {
        my $workflow = Workflow::Operation->create_from_xml($xml_file);
        confess "Could not create workflow!" unless $workflow;

        # FIXME Temp directory shouldn't be hard-coded
        my $tempdir = tempdir(
            CLEANUP => 0, 
            DIR => '/gscmnt/temp212/info/annotation/pap_workflow_logs/',
        );
        chmod(0755, $tempdir);
        $workflow->log_dir($tempdir);

        # TODO Implement dynamic workflow generation to allow an arbitrary combo of tools to be used
        my %workflow_params = (
            'fasta file' => $fasta_file,
            'chunk size' => 1000,
            'dev flag' => $workflow_dev_flag,
            'biosql namespace' => 'MGAP',
            'gram stain' => $self->gram_stain(),
            'interpro archive dir' => $self->interpro_archive_dir(),
            'keggscan archive dir' => $self->keggscan_archive_dir(),
            'psortb archive dir' => $self->psortb_archive_dir(),
			'locus tag'			  => $self->locus_tag(),
        );

        $self->status_message("Kicking off PAP workflow!");

        $output = run_workflow_lsf(
            $workflow,
            %workflow_params,
        );
    }

    if (defined $output) {
        $self->status_message("Protein annotation workflow completed successfully!");
    }
    else {
        for my $error (@Workflow::Simple::ERROR) {
            my @attributes = grep { defined $error->$_ } qw/ dispatch_identifier name start_time end_time exit_code /;
            $self->status_message(join("\t", @attributes));
            $self->status_message(join("\t", map {$error->$_} @attributes));
            $self->status_message($error->stdout);
            $self->status_message($error->stderr);
        }
        confess 'Protein annotation workflow errors encountered, see above error messages!';
    }
    return 1;
}


sub activity_log
{
    my $self = shift;
    my ($run_time, $locus_tag) = @_;
    my $sequence_id   = $self->sequence_set_id;
    my $organism_name = $self->organism_name;
    my $sequence_name = $self->sequence_name;

    if($self->dev)
    {
        return 1;

    }
    #use BAP::DB::Organism;
    #my ($organism) = BAP::DB::Organism->search({locus => $locus_tag});
    #my $organism_name;
    #if($organism)
    #{
    #    $organism_name = $organism->organism_name;
    #}
    #else
    unless ($organism_name)
    {
        carp "Couldn't get organism name for activity logging, will continue logging with locus tag, instead ... from SendToPap.pm\n";
        $organism_name = $locus_tag;
    }
    $locus_tag =~ s/(DFT|FNL|MSI)$//;
    my $db_file = '/gscmnt/temp212/info/annotation/BAP_db/mgap_activity.db';
    my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file",'','',
                           {RaiseError => 1, AutoCommit => 1});
    unless(defined($dbh))
    {
        return 0;
    }
    my $sql = <<SQL;
    INSERT INTO activity_log (activity,
                              sequence_id,
                              sequence_name,
                              organism_name,
                              host,
                              user,
                              started,
                              finished)
        VALUES (?,?,?,?,?,?,
                strftime('%s', 'now') - $run_time,
                strftime('%s', 'now')
        );
SQL

    my $host = undef;
    my $user = undef;

    if (exists($ENV{LSB_HOSTS}) )
    {
        $host = $ENV{LSB_HOSTS};
    }
    elsif (exists($ENV{HOST}) )
    {
        $host = $ENV{HOST};
    }

    if (Genome::Sys->username)
    {
        $user = Genome::Sys->username;
    }
    elsif (exists($ENV{LOGIN}) )
    {
        $user = $ENV{LOGIN};
    }
    elsif (exists($ENV{USERNAME}) )
    {
        $user = $ENV{USERNAME};
    }


    if(!$self->dev)
    {

        $dbh->do($sql, {},
                 'protein annotation',$sequence_id,$sequence_name,
                 $organism_name,
                 $host, $user);

    }
    return 1;
}

1;

# $Id$
