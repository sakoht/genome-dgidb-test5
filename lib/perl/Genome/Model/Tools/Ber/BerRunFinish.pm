package Genome::Model::Tools::Ber::BerRunFinish;

use strict;
use warnings;

use Genome;
use Command;

use Carp;
use English;

use BAP::DB::Sequence;
use BAP::DB::SequenceSet;
use BAP::DB::CodingGene;
use Ace;
use Ace::Object;
use Ace::Sequence;

use Data::Dumper;
use IO::File;
use IPC::Run qw/ run timeout /;
use Time::HiRes qw(sleep);
use DateTime;
use MIME::Lite;

use File::Slurp;    # to replace IO::File access...
use File::Copy;
use File::Basename;

use Cwd;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is         => 'Command',
    has        => [
        'locus_tag' => {
            is  => 'String',
            doc => "Locus tag for project, containing DFT/FNL postpended",
        },
        'outdirpath' => {
            is  => 'String',
            doc => "output directory for the ber product naming software",
        },
        'sqlitedatafile' => {
            is  => 'String',
            doc => "Name of sqlite output .dat file",
        },
        'sqliteoutfile' => {
            is  => 'String',
            doc => "Name of sqlite output .out file",
        },
        'acedb_version' => {
            is  => 'String',
            doc => "Current acedb version",
        },
        'amgap_path' => {
            is  => 'String',
            doc => "Current path to AMGAP data",
        },
        'pipe_version' => {
            is  => 'String',
            doc => "Current pipeline version running",
        },
        'project_type' => {
            is  => 'String',
            doc => "Current project type",
        },
        'org_dirname' => {
            is  => 'String',
            doc => "Current organism directory name",
        },
        'assembly_name' => {
            is  => 'String',
            doc => "Current assembly name",
        },
        'sequence_set_id' => {
            is  => 'String',
            doc => "Current sequence set id",
        },
    ]
);

sub help_brief
{
    "Tool for making the final BER ace file, write new parse script and parse into acedb via tace, gather stats from phase5 ace file and acedb, writes the rt file and mails when finished ";
}

sub help_synopsis
{
    return <<"EOS"
      Tool for making the final BER ace file, write new parse script and parse into acedb via tace, gather stats from phase5 ace file and acedb, writes the rt file and mails when finished.
EOS
}

sub help_detail
{
    return <<"EOS"
Tool for making the final BER ace file, write new parse script and parse into acedb via tace, gather stats from phase5 ace file and acedb, writes the rt file and mails when finished.
EOS
}

sub execute
{
    my $self          = shift;
    my $locus_tag     = $self->locus_tag;
    my $outdirpath    = $self->outdirpath;
    my $sqlitedata    = $self->sqlitedatafile;
    my $sqliteout     = $self->sqliteoutfile;
    my $acedb_ver     = $self->acedb_version;
    my $amgap_path    = $self->amgap_path;
    my $pipe_version  = $self->pipe_version;
    my $project_type  = $self->project_type;
    my $org_dirname   = $self->org_dirname;
    my $assembly_name = $self->assembly_name;
    my $ssid          = $self->sequence_set_id;

    my $anno_submission = $amgap_path . "/"
        . $org_dirname . "/"
        . $assembly_name . "/"
        . $pipe_version . "/"
	. "Genbank_submission/Version_1.0/Annotated_submission/";

    my $program = "/gsc/scripts/bin/tace";
    my $cwd     = getcwd();
    my $outdir
		= qq{/gscmnt/temp110/info/annotation/ktmp/BER_TEST/hmp/autoannotate/out};
    unless ( $cwd eq $outdir )
    {
        chdir($outdir)
            or die
            "Failed to change to '$outdir'...  from BerRunFinish.pm: $OS_ERROR\n\n";
    }

    my $sqlitedatafile = qq{$outdirpath/$sqlitedata};
    # recent versions of BER try to be helpful and append '.dat' to dat files
    # then we get .dat.dat on the ends of the files.
    if(-f $sqlitedatafile.".dat") {
        # rename file.
        rename($sqlitedatafile.".dat",$sqlitedatafile);
    }
    
    ## get the latest filename
    (my $sqlitedatafilename, $outdirpath) = fileparse($sqlitedatafile);

    ## Copy sqlite.dat file Annotated_submission directory
    ## Before copying sqlite file we will need to delete sqlite*.dat && *.dat.dat file in the Annotated_submission directory if already exists
 	unlink($anno_submission.$sqlitedatafilename) || croak qq{\n\n Cannot delete $anno_submission.$sqlitedatafilename ... from BerRunFinish.pm: $OS_ERROR\n\n} if -e $anno_submission.$sqlitedatafile;
 	unlink($anno_submission.$sqlitedatafilename.".dat") || croak qq{\n\n Cannot delete $anno_submission.$sqlitedatafilename ... from BerRunFinish.pm: $OS_ERROR\n\n} if -e $anno_submission.$sqlitedatafilename.".dat";
    copy($sqlitedatafile, $anno_submission.$sqlitedatafilename) || croak qq{\n\n Copying of $sqlitedatafile failed ...  from BerRunFinish.pm: $OS_ERROR\n\n };

    my $sqliteoutfile  = qq{$outdirpath/$sqliteout};
    unless ( ( -e $sqlitedatafile ) and ( !-z $sqlitedatafile ) )
    {
        croak
            qq{\n\n NO file,$sqlitedatafile, found for or empty ... from BerRunFinish.pm: $OS_ERROR\n\n };
    }

    my $acedb_short_ver = $self->version_lookup( $self->acedb_version );
    my $acedb_data_path = $self->{amgap_path}
        . "/Acedb/"
        . $acedb_short_ver
        . "/ace_files/"
        . $self->locus_tag . "/"
        . $self->pipe_version;
    unless ( -d $acedb_data_path )
    {
        croak
            qq{\n\n NO acedb_dir_path, $acedb_data_path, found ... from BerRunFinish.pm: $OS_ERROR\n\n };
    }
    ################################
    # parse the sqlite data file
    ################################

    my $bpnace_fh = IO::File->new();
    my $bpname    = qq{_BER_product_naming.ace};
    my $bpn_file  = qq{$acedb_data_path/$locus_tag$bpname};
    $bpnace_fh->open("> $bpn_file")
        or die
        "Can't open '$bpn_file', bpn_file for writing ...from BerRunFinish.pm: $OS_ERROR\n\n";

    my $data_fh = IO::File->new();
    $data_fh->open("< $sqlitedatafile")
        or die
        "Can't open '$sqlitedatafile',sqlite data file ...from BerRunFinish.pm: $OS_ERROR\n\n";

    # FIXME
    # this could be cleaned up with read_file/write_file and Text::CSV_XS...
    while (<$data_fh>)
    {
        my ($featname,   $proteinname, $genesymbol, $go_terms,
            $ec_numbers, $t_equivalog, $speciesname
            )
            = split( /\t/, $ARG );
        print $bpnace_fh "Sequence ", $featname, "\n";
        print $bpnace_fh "BER_product " , "\"$proteinname\"", "\n\n";
    }
    $bpnace_fh->close();
    $data_fh->close();
    ########################################################
    # check acedb readlock before proceeding
    ########################################################

    $cwd = getcwd();

    # is $self->{amgap_path} legal here???
    my $acedb_readlock_path = $self->{amgap_path}
        . "/Acedb/"
        . $acedb_short_ver
        . "/database/readlocks";
    unless ( $cwd eq $acedb_readlock_path )
    {
        chdir($acedb_readlock_path)
            or die
            "Failed to change to '$acedb_readlock_path'...  from BerRunFinish.pm: $OS_ERROR\n\n";
    }

    #FIXME
    # oh, shit, not again.
    # File::Find on the acedb_readlock_path, and push into @readlock
    # this should also be in it's own subroutine for easier testing
    while (1)
    {
        opendir( DIR, $acedb_readlock_path )
            or die
            "Can't open '$acedb_readlock_path'... from BerRunFinish.pm: $OS_ERROR\n\n";
        my @readlock = ();
        while ( defined( my $file = readdir DIR ) )
        {
            next if $file =~ m/^\.\.?$/;
            push( @readlock, $file );
        }
        closedir(DIR);
        my ( $readlock_fh, $session, $machine, $gsc, $wustl, $edu, $process );
        if (@readlock)
        {
            foreach my $lockfile (@readlock)
            {
                ( $session, $machine, $gsc, $wustl, $edu, $process )
                    = split /\./, $lockfile;
                $machine = join( '.', $machine, $gsc, $wustl, $edu );
                $readlock_fh = IO::File->new();
                $readlock_fh->open("< $lockfile")
                    or die
                    "Can't open '$readlock_fh', readlock_fh for reading ...from BerRunFinish.pm: $OS_ERROR\n\n";
            }
            my %readlock = ();
            while (<$readlock_fh>)
            {
                chomp $ARG;
                if (   $ARG !~ /^[\#\s\t\n]/
                    && $ARG =~ /^([^\:]+)\:([^\n\#]*)/ )
                {
                    my $key   = $1;
                    my $value = $2;

                    #remove preceding and trailing whitespace
                    $value =~ s/^[\s\t]+|[\s\t]+$//g;

                    #set value
                    $readlock{$key} = defined($value) ? $value : '';
                }
            }
            print
                qq{\n\nACeDB Session number: $session is currently readlocked by: $readlock{User} on $readlock{Created} using machine:$machine (process ID is: $process)\n};
            sleep(300);
            next;
        }
        else
        {
            print qq{\n No readlock detected, continuing to next step....\n};
            last;
        }
    }
    ########################################################
    # check acedb via tace for previous data and remove it
    ########################################################
    # this should be in a separate sub too...
    $cwd = getcwd();
    my $acedb_maindir_path
        = $self->{amgap_path} . "/Acedb/" . $acedb_short_ver;
    unless ( $cwd eq $acedb_maindir_path )
    {
        chdir($acedb_maindir_path)
            or die
            "Failed to change to '$acedb_maindir_path'...  from BerRunFinish.pm: $OS_ERROR\n\n";
    }

    #connecting to acedb database
    my $db = Ace->connect(
        -path    => "$acedb_maindir_path",
        -program => "$program"
        )
        or die
        "ERROR: cannot connect to acedb ... from BerRunFinish.pm: $OS_ERROR\n \n";

    #mining data from acedb
    my @ace_objects = $db->fetch(
        -name  => "$locus_tag*",
        -class => 'Sequence',
    );

    #my @ace_objects = $db->fetch(
    #	                           -name    => "$locus_tag*",
    #				   -class   => 'Sequence',
    #				   -filltag => 'Visible',
    #			          );

    if ( defined(@ace_objects) )
    {
        foreach my $ace_stuff (@ace_objects)
        {
            my $aceseq_obj = $db->fetch( 'Sequence' => $ace_stuff );
            my $BER_product = $aceseq_obj->BER_product();
            if ( defined($BER_product) )
            {
                my $result_code = $aceseq_obj->kill();
            }
            else
            {
                next;
            }
        }
    }
    print qq{\n Done checking/removing previous data from ACeDB\n\n};

    ########################################################
    # write new parse script and parse into acedb via tace
    ########################################################
    # separate subroutine again...
    $cwd                = getcwd();
    $acedb_maindir_path = $self->{amgap_path} . "/Acedb/" . $acedb_short_ver;
    unless ( $cwd eq $acedb_maindir_path )
    {
        chdir($acedb_maindir_path)
            or die
            "Failed to change to '$acedb_maindir_path'...  from BerRunFinish.pm: $OS_ERROR\n\n";
    }

    my $acedb_scripts_path = $self->{amgap_path} . "/Acedb/Scripts";
    my $parse_script_name
        = "parsefiles_pap_ber_" . $locus_tag . "_" . $pipe_version . ".sh";
    my $parse_script_full = qq{$acedb_scripts_path/$parse_script_name};
    my $parse_script_fh   = IO::File->new();
    $parse_script_fh->open("> $parse_script_full")
        or die
        "Can't open '$parse_script_full', parse_script_full for writing ...from BerRunFinish.pm: $OS_ERROR\n\n";

    opendir( ACEDATA, $acedb_data_path )
        or die
        "Can't open $acedb_data_path, acedb_data_path from BerRunFinish.pm: $OS_ERROR\n";

    my @acefiles = ();
    @acefiles = readdir(ACEDATA);
    closedir(ACEDATA);

    my $phase5file = $locus_tag . "_phase_5_ssid_";

    my $parse = "parse";
    print $parse_script_fh "#!/bin/sh -x\n\n";
    print $parse_script_fh
        "#if you call script from bash, tace will follow links!\n\n";
    print $parse_script_fh "TACE=/gsc/scripts/bin/tace\n";
    print $parse_script_fh "ACEDB=`pwd`\n\n";
    print $parse_script_fh "export ACEDB\n\n";
    print $parse_script_fh "echo \$acedb\n\n";
    print $parse_script_fh "\$TACE << EOF\n\n";

    my $shortph5file;
    foreach my $acefile (@acefiles)
    {
        next if $acefile =~ /^\.\.?$/;
        next if $acefile =~ /\.gff$|\.fasta$|\.genomic_canonical\.ace$/;
        next if $acefile =~ /\.txt$/;
        next if $acefile =~ m/dead_genes_list/;

        if ( $acefile =~ /$phase5file/ )
        {
            $shortph5file = $phase5file = $acefile;
        }

        next if $acefile =~ /_phase_[0-5]_ssid_/;
        print $parse_script_fh "$parse  $acedb_data_path/$acefile\n";
    }
    print $parse_script_fh "\nsave\n";
    print $parse_script_fh "quit\n\n";
    print $parse_script_fh "EOF\n\n";
    print $parse_script_fh
        "echo \"Parsing of HGMI_$locus_tag $pipe_version files, complete.\" | mailx -s \"HGMI_$locus_tag $pipe_version\" ssurulir\n";

    $parse_script_fh->close();

    my $mode = 0775;
    chmod $mode, $parse_script_full;
    my $aceparce_stdout
        = $acedb_data_path . "/STDOUT_" . $locus_tag . "_ace_parse.txt";

    my @aceparcecmd = ( $parse_script_full, );

    my $aceparse_stderr;
    IPC::Run::run( \@aceparcecmd, '>', \$aceparce_stdout, '2>',
        \$aceparse_stderr, )
        or die "problem: $aceparse_stderr";

    ########################################################
    # gather stats from phase5 ace file and acedb
    ########################################################
    $phase5file = qq{$acedb_data_path/$phase5file};

    unless ( ( -e $phase5file ) and ( !-z $phase5file ) )
    {
        croak
            qq{\n\n NO file,$phase5file,(phase5file) found  or else empty ... from BerRunFinish.pm: $OS_ERROR\n\n };
    }

    my $phase5ace_fh = IO::File->new();
    $phase5ace_fh->open("< $phase5file")
        or die
        "Can't open '$phase5file', phase5file for reading ...from BerRunFinish.pm: $OS_ERROR\n\n";

    my @phase5acecount = ();
    while (<$phase5ace_fh>)
    {
        chomp $ARG;
        if ( $ARG =~ /Subsequence/ )
        {
            push( @phase5acecount, $ARG );
        }
    }
    $phase5ace_fh->close();

    my $acefilecount = scalar(@phase5acecount);
    $db = Ace->connect(
        -path    => "$acedb_maindir_path",
        -program => "$program",
        )
        or die
        "ERROR: cannot connect to acedb ...from BerRunFinish.pm: $OS_ERROR\n \n";

    my @trna_all_d
        = $db->fetch( -query => "Find Sequence $locus_tag\_C*.t* & ! Dead" );
    my @rfam_all_d = $db->fetch(
        -query => "Find Sequence $locus_tag\_C*.rfam* & ! Dead" );
    my @rnammer_all_d = $db->fetch(
        -query => "Find Sequence $locus_tag\_C*.rnammer* & ! Dead" );
    my @orfs_d = $db->fetch(
        -query => "Find Sequence $locus_tag\_C*.p5_hybrid* & ! Dead" );

    my $Totals_not_dead      = 0;
    my $Totals_not_dead_rna  = 0;
    my $Totals_not_dead_orfs = 0;

    $Totals_not_dead
        = scalar(@rfam_all_d) + scalar(@rnammer_all_d) + scalar(@trna_all_d) +
        scalar(@orfs_d);
    $Totals_not_dead_rna
        = scalar(@rfam_all_d) + scalar(@rnammer_all_d) + scalar(@trna_all_d);
    $Totals_not_dead_orfs = scalar(@orfs_d);

    my @trna_all = $db->fetch( -query => "Find Sequence $locus_tag\_C*.t*" );
    my @rfam_all
        = $db->fetch( -query => "Find Sequence $locus_tag\_C*.rfam*" );
    my @rnammer_all
        = $db->fetch( -query => "Find Sequence $locus_tag\_C*.rnammer*" );
    my @orfs
        = $db->fetch( -query => "Find Sequence $locus_tag\_C*.p5_hybrid*" );

    my $Totals_with_dead      = 0;
    my $Totals_with_dead_rna  = 0;
    my $Totals_with_dead_orfs = 0;

    $Totals_with_dead
        = scalar(@rfam_all) + scalar(@rnammer_all) + scalar(@trna_all) +
        scalar(@orfs);
    $Totals_with_dead_rna
        = scalar(@rfam_all) + scalar(@rnammer_all) + scalar(@trna_all);
    $Totals_with_dead_orfs = scalar(@orfs);

    print "\n\n" . $locus_tag . "\n\n";
    print $acefilecount
        . "\tSubsequence counts from acefile $shortph5file\n\n";
    print $Totals_not_dead
        . "\tp5_hybrid counts from ACEDB  orfs plus RNA's that are NOT dead genes\n";
    print $Totals_not_dead_rna
        . "\tp5_hybrid counts from ACEDB for ALL RNA's that are NOT dead genes\n";
    print $Totals_not_dead_orfs
        . "\tp5_hybrid counts from ACEDB orfs minus RNA's that are NOT dead genes\n\n";
    print $Totals_with_dead
        . "\tp5_hybrid counts from ACEDB orfs plus RNA's with dead genes (should match acefile $shortph5file)\n";
    print $Totals_with_dead_rna
        . "\tp5_hybrid counts from ACEDB for ALL RNA's with dead genes\n";
    print $Totals_with_dead_orfs
        . "\tp5_hybrid counts from ACEDB orfs with dead genes\n\n";

    if ( $acefilecount == $Totals_with_dead )
    {

        print
            "p5_hybrid ace file counts match p5_hybrid counts in ACEDB... Good :) \n\n";

    }
    else
    {
        print $acefilecount, " ", $Totals_with_dead, "\n";
        print
            "HOUSTON, WE HAVE A PROBLEM, p5_hybrid ace file counts DO NOT MATCH p5_hybrid counts in ACEDB (Totals_with_dead)... BAD :(\n\n";

    }
#
    ## We will dump gff for this genome
    unless ( $cwd eq $acedb_data_path )
    {
        chdir($acedb_data_path)
            or die
            "Failed to change to '$acedb_data_path'...  from BerRunFinish.pm: $OS_ERROR\n\n";
    }

    my $gff_dump_file = $locus_tag ."_phase_5_ssid_". $ssid. ".gff";
	my $bap_dump_gff_cmd = "bap_dump_gene_predictions_gff --sequence-set-id $ssid > $gff_dump_file";
#print "Dumping gff dump (cmd): ". $bap_dump_gff_cmd."\n";
	system("$bap_dump_gff_cmd") == 0
			or die "system $bap_dump_gff_cmd failed: $?";

    ## List dead genes
    my $dead_genes_file = $locus_tag."_dead_genes_list";
    my $dead_genes_cmd = " bap_list_dead_genes --sequence-set-id $ssid > $dead_genes_file";
#    print "Running bap_list_dead_genes (cmd): ". $dead_genes_cmd. "\n";
    system("$dead_genes_cmd") == 0
			or die "system $bap_dump_gff_cmd failed: $?";

    ## Count the dead genes - depends on number of lines
     my $dead_genes = `wc -l < $dead_genes_file` ||
            die "wc failed: $?\n";
    chomp($dead_genes);

    ########################################################
    # Writing the rt file
    ########################################################

    my $rtfilename = $project_type
        . "_rt_let_"
        . $locus_tag . "_"
        . $pipe_version . ".txt";
    my $rtfileloc
        = $amgap_path . "/Acedb/Scripts/" . $project_type . "_files";
    my $rtfullname = qq{$rtfileloc/$rtfilename};
    my $rtfile_fh  = IO::File->new();
    $rtfile_fh->open("> $rtfullname")
        or die
        "Can't open '$rtfullname', rtfullname for writing ...from BerRunFinish.pm: $OS_ERROR\n\n";

    print $rtfile_fh
        qq{\n$assembly_name, $locus_tag, a $project_type project has finished processing in AMGAP, BER product naming and now ready to be processed for submissions\n\n};

    print $rtfile_fh qq{\nA copy of BER naming file $sqlitedatafilename has been placed in $anno_submission$sqlitedatafilename\n\n};


    my $sequence_set     = BAP::DB::SequenceSet->retrieve($ssid);
    my $software_version = $sequence_set->software_version();
    my $data_version     = $sequence_set->data_version();

    print $rtfile_fh qq{BAP/MGAP Version: $software_version }, "\n";
    print $rtfile_fh qq{Data Version: $data_version},          "\n\n";
    print $rtfile_fh qq{Location:\n\n};

    my $location = $amgap_path . "/"
        . $org_dirname . "/"
        . $assembly_name . "/"
        . $pipe_version;

    print $rtfile_fh qq{$location\n\n};
    print $rtfile_fh
        qq{Gene prediction by the following programs has been run via bap_predict_genes:\n\n};
    print $rtfile_fh qq{Glimmer3\n};
    print $rtfile_fh qq{GeneMark\n};
    print $rtfile_fh qq{trnascan\n};
    print $rtfile_fh qq{RNAmmer\n};
    print $rtfile_fh qq{Rfam v8.1, with Rfam_product\n\n};
    print $rtfile_fh
        qq{bap_merge_genes has been run and includes blastx through phase_5\n\n};
    print $rtfile_fh qq{Here are the gene counts from Oracle AMGAP:\n\n};

    my @sequences        = $sequence_set->sequences();
    my $blastx_counter   = 0;
    my $glimmer2_counter = 0;
    my $glimmer3_counter = 0;
    my $genemark_counter = 0;

    foreach my $i ( 0 .. $#sequences )
    {
        my $sequence     = $sequences[$i];
        my @coding_genes = $sequence->coding_genes();
        foreach my $ii ( 0 .. $#coding_genes )
        {
            my $coding_gene = $coding_genes[$ii];
            if ( $coding_gene->source() =~ 'blastx' )
            {
                $blastx_counter++;
            }
            elsif ( $coding_gene->source() =~ 'glimmer3' )
            {
                $glimmer3_counter++;
            }
            else
            {
                $genemark_counter++;
            }
        }
    }

    print $rtfile_fh qq{blastx count   =\t $blastx_counter},   "\n";
    print $rtfile_fh qq{GeneMark count =\t $genemark_counter}, "\n";
    print $rtfile_fh qq{Glimmer3 count =\t $glimmer3_counter}, "\n\n";
    print $rtfile_fh
        qq{Protein analysis by the following programs has been run via PAP workflow:\n\n};
    print $rtfile_fh qq{Interpro v4.5 (database v22.0)\n};
    print $rtfile_fh qq{Keggscan v52\n};
    print $rtfile_fh qq{psortB v3.0\n};
    print $rtfile_fh qq{Blastp\n\n};
    print $rtfile_fh
        qq{Location of AMGAP ace files can be located, here:\n\n};
    print $rtfile_fh qq{$acedb_data_path\n\n};

    foreach my $acefile (@acefiles)
    {
        next if $acefile =~ /^\.\.?$/;
        next if $acefile =~ /\.gff$/;
        next if $acefile =~ /\.txt$/;
        print $rtfile_fh "$acefile\n";
    }

    print $rtfile_fh
        qq{\n$locus_tag, QC ace file gene counts verses ACEDB gene counts},
        "\n\n";
    print $rtfile_fh qq{$acefilecount\tgenes from acefile $shortph5file},
        "\n\n";
    print $rtfile_fh
        qq{$Totals_not_dead\tp5_hybrid genes from ACEDB orfs plus RNA\'s that are NOT dead genes},
        "\n";
    print $rtfile_fh
        qq{$Totals_not_dead_rna\tp5_hybrid genes from ACEDB for ALL RNA\'s that are NOT dead genes},
        "\n";
    print $rtfile_fh
        qq{$Totals_not_dead_orfs\tp5_hybrid genes from ACEDB orfs minus RNA\'s that are NOT dead genes minus RNA\'s},
        "\n\n";
    print $rtfile_fh
        qq{$Totals_with_dead\tp5_hybrid genes from ACEDB orfs plus RNA\'s with dead genes (should match acefile $shortph5file ) },
        "\n";
    print $rtfile_fh
        qq{$Totals_with_dead_rna\tp5_hybrid genes from ACEDB for ALL RNA\'s with dead genes},
        "\n";
    print $rtfile_fh
        qq{$Totals_with_dead_orfs\tp5_hybrid genes from ACEDB orfs with dead genes minus RNA\'s},
        "\n\n";

    if ( $acefilecount == $Totals_with_dead )
    {
        print $rtfile_fh
            qq{p5_hybrid ace file counts match p5_hybrid counts in ACEDB... Good :) },
            "\n\n";
    }
    else
    {
        print $rtfile_fh
            qq{HOUSTON, WE HAVE A PROBLEM, p5_hybrid ace file counts DO NOT MATCH p5_hybrid counts in ACEDB (Totals_with_dead)... BAD :\(  },
            "\n\n";
    }
    print $rtfile_fh qq{GFF dump for thus genome can be downloaded from: $acedb_data_path/$gff_dump_file\n\n};
    
    ## Dead gene stuff
    if ($dead_genes) {
    	print $rtfile_fh qq{Further I found $dead_genes gene tagged as 'Dead'\n};
        open (DG, $dead_genes_file) || die ("Error opening $dead_genes_file :$?\n");
		while (<DG>) {
			chomp;
            print $rtfile_fh qq{$_\n};
		}
	}
    
    print $rtfile_fh qq{\nLocation of this file: $rtfullname\n\n};
    print $rtfile_fh qq{I am transferring ownership to Veena/Joanne.\n\n};
    print $rtfile_fh qq{Thanks,\n\n};
    print $rtfile_fh qq{Sasi\n};

    send_mail( $ssid, $assembly_name, $rtfileloc, $rtfilename, $rtfullname );

    return 1;
}

################################################
################################################

sub version_lookup
{
    my $self           = shift;
    my $v              = shift;
    my $lookup         = undef;
    my %version_lookup = (
        'V1' => 'Version_1.0',
        'V2' => 'Version_2.0',
        'V3' => 'Version_3.0',
        'V4' => 'Version_4.0',
        'V5' => 'Version_5.0',
        'V6' => 'Version_6.0',
        'V7' => 'Version_7.0',
        'V8' => 'Version_8.0',
    );

    if ( exists( $version_lookup{$v} ) )
    {
        $lookup = $version_lookup{$v};
    }
    else
    {
        $v =~ s/V(\d+)/Version_$1.0/;
        $lookup = $v;
    }

    return $lookup;
}

sub send_mail
{

    my ( $ssid, $assembly_name, $rtfileloc, $rtfilename, $rtfullname ) = @ARG;
    my $from
        = join( ', ', 'ssurulir@watson.wustl.edu',
        );

    my $to = join( ', ',
#'kpepin@genome.wustl.edu',
        'ssurulir@watson.wustl.edu',);

    my $subject
        = "Amgap BER Product Naming script mail for AMGAP SSID: $ssid ($assembly_name)";

    my $body = <<BODY;
The Amgap BER Product Naming script has finished running for MGAP SSID: $ssid ($assembly_name).
The information for the rt ticket has been attached:

File: $rtfilename

Path: $rtfileloc
BODY

    my $msg = MIME::Lite->new(
        From    => $from,
        To      => $to,
        Subject => $subject,
        Data    => $body,
    );
    $msg->attach(
        Type        => "text/plain",
        Path        => $rtfullname,
        Filename    => $rtfilename,
        Disposition => "attachment",
    );

    $msg->send();
    return 1;
}

1;
