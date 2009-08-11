package Genome::Model::Tools::Ber::AmgapBerProtName;

use strict;
use warnings;

use Genome;
use Command;

use Genome::Model::Tools::Ber::AmgapPrepareBER;
use Genome::Model::Tools::Ber::AmgapDumpProteinBiosql;
use Genome::Model::Tools::Ber::BerRunBlastphmmpfam;
use Genome::Model::Tools::Ber::BerRunBtabhmmtab;
use Genome::Model::Tools::Ber::BerRunAnnoSqlite;
use Genome::Model::Tools::Ber::BerRunFinish;

use Carp;
use File::Path qw(mkpath);
use File::Spec;
use Cwd;
use YAML qw( LoadFile );
use English;

UR::Object::Type->define(
			 class_name => __PACKAGE__,
			 is         => 'Command',
			 has        => [
					'sequence_set_id' => {
							      is  => 'Integer',
							      doc => "Sequence set id from Oracle database.",
							     },
					'config'          => { 
							      is => 'String',
							      doc => "YAML file for reading.  This is the same config file used to start AMGAP.",
							     },
					'internalhash'    => {
							      is => 'HashRef',
							      doc => "internal",
							      is_optional => 1,
							     },
					'phase'          =>{
							    is          => 'Interger',
							    doc         => "Phase of protein to dump from Oracle.  Default is phase 5. ",
							    default     => 5,
							    is_optional => 1,
							   },
				       ]
			);

sub help_brief
{
    "Runs the entire BER product naming pipeline";
}

sub help_synopsis
{
    return <<"EOS"
Runs the entire BER product naming pipeline. This tool pulls data from biosql, runs blastp, hmmpfam, btab, hmmtab and anno-sqlite.bash.
EOS
}

sub help_detail
{
    return <<"EOS"
Runs the entire BER product naming pipeline. This tool pulls data from biosql, runs blastp, hmmpfam, btab, hmmtab and anno-sqlite.bash.  In addition, this script will also create the BER_product_naming.ace file, writes the tace script, parses all ace files into acedb, gathers QC stats from the phase5 file and queries acedb to make sure gene counts match, then writes the rt ticket blurb and mails the user when finished.
EOS
}

sub execute
{
    my $self = shift;

    if(-f $self->config)
    {
        $self->internalhash(LoadFile($self->config));
    }
    else
    {
        # blow up...
        my $file = $self->config;
        carp "non-existent file $file Berpn.pm\n\n";
        return 0;
    }

    my $config = $self->internalhash;

    ################################################
    #Prepare BER
    ################################################
    my $cwd        = getcwd();
    my $berbasedir = qq{/gscmnt/temp110/info/annotation/ktmp/BER_TEST/hmp/autoannotate};
    my $configdir  = qq{$berbasedir/data/db/CSV};

    unless ( -d $configdir ){

      croak qq{The directory: '$configdir', does not exist, from  AmgapPrepareBER.pm: $OS_ERROR};

    }

    unless ( $cwd eq $configdir  ) {

      chdir($configdir)  or croak "Failed to change to '$configdir', from  AmgapBerProtName.pm: $OS_ERROR";

    }

    warn qq{\nPreparing BER config files and directory structure...\n\n};

    my $apber = Genome::Model::Tools::Ber::AmgapPrepareBER->create(
								   'locus_tag'        => $config->{locus_tag},
								   'sequence_set_id'  => $self->sequence_set_id,
								   'phase'            => $self->phase,
								  );
    if ($apber)
      {
	$apber->execute() or croak "\nCan't run AmgapPrepareBER.pm ... from AmgapBerProtName.pm\n\n";

      } else {
	croak "Can't set up AmgapPrepareBER.pm ... from AmgapBerProtName.pm\n\n";
      }
    ################################################
    #Amgap Dump Protein Biosql
    ################################################

    my $genomesdir  = qq{$berbasedir/data/genomes};
    my $locustagdir = qq{$genomesdir/$config->{locus_tag}};
    my $fastadir    = qq{$locustagdir/fasta};
    my $berdir      = qq{$locustagdir/ber};
    my $hmmdir      = qq{$locustagdir/hmm};
    my $bsubfiledir = qq{$locustagdir/bsubERRfiles};
    my $blpqf       = qq{/gscmnt/temp110/info/annotation/ktmp/BER_TEST/hmp/autoannotate/data/panda/AllGroup/AllGroup.niaa};
    #my $hmmdb       = qq{/gscmnt/temp110/info/annotation/ktmp/BER_TEST/hmp/autoannotate/data/ALL_LIB.20081108.HMM};
    my $hmmdb       = qq{/gscmnt/temp110/info/annotation/ktmp/BER_TEST/hmp/autoannotate/data/ALL_LIB.HMM};


    chdir($genomesdir) or croak  "\nFailed to change directories to '$genomesdir' ... from AmgapBerProtName.pm: $OS_ERROR\n\n";

    unless (-d $locustagdir) {
      mkdir $locustagdir or croak "Failed to create '$locustagdir', from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }
    unless (-d $fastadir) {
      mkdir $fastadir or croak "Failed to create '$fastadir', from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }
    unless (-d $berdir ) {
      mkdir $berdir or croak "Failed to create '$berdir', from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }
    unless (-d $hmmdir ) {
      mkdir $hmmdir or croak "Failed to create '$hmmdir', from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }
    unless (-d $bsubfiledir ) {
      mkdir $bsubfiledir or croak "Failed to create '$bsubfiledir', from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }
    unless ( -e $blpqf ) {
	croak "Failed to find '$blpqf', from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }
    unless ( -e $hmmdb ) {
	croak "Faild to find '$hmmdb', from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }

     chdir($fastadir) or croak  "\nFailed to change directories to '$genomesdir' ... from AmgapBerProtName.pm: $OS_ERROR\n\n";

    warn qq{Dumping protein from BioSQL...\n\n};

    my $adpb = Genome::Model::Tools::Ber::AmgapDumpProteinBiosql->create(
									 'locus_tag'  => $config->{locus_tag},
									);

    if ($adpb) {
      $adpb->execute() or croak "\nCan't run AmgapDumpProteinBiosql.pm ... from AmgapBerProtName.pm\n\n";
    } else {
      croak "Can't set up AmgapDumpProteinBiosql.pm ... from AmgapBerProtName.pm\n\n";
    }
    ################################################
    #Ber Run Blastp hmmpfam
    ################################################
    $cwd = getcwd();
    unless ( $cwd eq $fastadir ) {
      chdir($fastadir)  or croak "Failed to change to '$fastadir', from  AmgapBerProtName.pm: $OS_ERROR";
    }

    warn qq{Running blastp and hmmpfam...\n\n};

    my $brbh = Genome::Model::Tools::Ber::BerRunBlastphmmpfam->create(
								      'locus_tag'       => $config->{locus_tag},
								      'proteinnamefile' => $adpb->proteinnamefile,
								      'fastadirpath'    => $fastadir,
								      'berdirpath'      => $berdir,
								      'hmmdirpath'      => $hmmdir,
								      'bsubfiledirpath' => $bsubfiledir,
								      'blpqueryfile'    => $blpqf,
								      'hmmdatabase'     => $hmmdb,
								     );
    if ($brbh) {
      $brbh->execute() or croak "\nCan't run BerRunBlastphmmpfam.pm ... from AmgapBerProtName.pm: $OS_ERROR\n\n";
    } else {
      croak "Can't set up BerRunBlastphmmpfam.pm ... from AmgapBerProtName.pm: $OS_ERROR\n\n";
      }
    ################################################
    #Ber Run Btap Htab
    ################################################
    $cwd = getcwd();
    my $srcdir = qq{/gscmnt/temp110/info/annotation/ktmp/BER_TEST/hmp/autoannotate/src};
    unless ($cwd eq $srcdir) {
	chdir($srcdir) or die "Failed to change to '$srcdir'...  from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }

    warn qq{Running Btab and Htab...\n\n};

    my $brbtht = Genome::Model::Tools::Ber::BerRunBtabhmmtab->create(
	                                                             'locus_tag'       => $config->{locus_tag},
								     'bsubfiledirpath' => $bsubfiledir,
								     'fastadirpath'    => $fastadir,
								     'berdirpath'      => $berdir,
								     'hmmdirpath'      => $hmmdir,
								     'srcdirpath'      => $srcdir,
								    );

    if ($brbtht) {
	$brbtht->execute() or croak "\nCan't run BerRunBtabhmmtab.pm ... from AmgapBerProtName.pm: $OS_ERROR\n\n";
    } else {
	croak "Can't set up BerRunBtabhmmtab.pm ... from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }

    $cwd = getcwd();
    unless ($cwd eq $srcdir) {
	chdir($srcdir) or die "Failed to change to '$srcdir'...  from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }
    warn qq{Running anno-sqlite.bash \n\n};

    my $outdir = qq{/gscmnt/temp110/info/annotation/ktmp/BER_TEST/hmp/autoannotate/out};

    my $bras =  Genome::Model::Tools::Ber::BerRunAnnoSqlite->create(
                                                                    'locus_tag'       => $config->{locus_tag},
								    'srcdirpath'      => $srcdir,
								    'outdirpath'      => $outdir,
                                                                   );

    if ($bras) {
	$bras->execute() or croak "\nCan't run BerRunAnnoSqlite.pm ... from AmgapBerProtName.pm: $OS_ERROR\n\n";
    } else {
	croak "Can't set up BerRunAnnoSqlite.pm ... from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }

    $cwd = getcwd();
    unless ($cwd eq $outdir) {
	chdir($outdir) or die "Failed to change to '$outdir'...  from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }

    warn qq{Running Finish...\n\n};

    my $brfin = Genome::Model::Tools::Ber::BerRunFinish->create(
	                                                        'locus_tag'       => $config->{locus_tag},
								'outdirpath'      => $outdir,
								'sqlitedatafile'  => $bras->sqlitedatafile,
								'sqliteoutfile'   => $bras->sqliteoutfile,
								'acedb_version'   => $config->{acedb_version},
								'amgap_path'      => $config->{path},
								'pipe_version'    => $config->{pipe_version},
								'project_type'    => $config->{project_type},
								'org_dirname'     => $config->{org_dirname},
								'assembly_name'   => $config->{assembly_name},
								'sequence_set_id' => $self->sequence_set_id,
							       );

    if ($brfin) {
	$brfin->execute() or croak "\nCan't run BerRunFinish.pm ... from AmgapBerProtName.pm: $OS_ERROR\n\n";
    } else {
	croak "Can't set up BerRunFinish.pm ... from AmgapBerProtName.pm: $OS_ERROR\n\n";
    }

    warn qq{\n\nThe Amgap BER Product Naming has finished, Thanks!\n\n};

    return 1;

}

################################################
################################################

sub read_config
{
    my $self = shift;
    
    my $conf = $self->config;
    unless(-f $conf)
    {
        carp "no config file $conf ... AmgapBerProtName.pm \n\n";
        return undef;
    }

    my $confhash = LoadFile($conf);

    return 1;
}


1;

# $Id$
