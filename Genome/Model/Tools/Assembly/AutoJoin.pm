package Genome::Model::Tools::Assembly::AutoJoin;

use strict;
use warnings;

use Genome;
use IO::File;
use Data::Dumper;
use Sort::Naturally;
use Cwd;
use Finishing::Assembly::Factory;
use Finishing::Assembly::ContigTools;

class Genome::Model::Tools::Assembly::AutoJoin {
    is => 'Command',
    has => [],
};

sub help_brief {
    'Tools to run autojoins'
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools assembly autojoins
EOS
}

sub create_alignments
{
    my ($self) = @_;

    #RESOLVE PATH TO DATA
    if ($self->dir) {
	my $dir = $self->dir;
	$self->error_message("Path must be edit_dir") and return
	    unless $dir =~ /edit_dir$/;
	$self->error_message("Invalid dir path: $dir") and return
	    unless -d $dir;
	chdir ("$dir");
    }
    else {
	my $dir = cwd();
	$self->error_message("You must be in edit_dir") and return
	    unless $dir =~ /edit_dir$/;
    }

    #ACE FILE
    my $ace_in = $self->ace;

    #CHECK TO MAKE SURE ACE FILE EXISTS
    unless (-s $ace_in) {
	$self->error_message("Invalid ace file: $ace_in");
	return;
    }

    #CAT ALL PHDBALL FILES TOGETHER IF PRESENT SINCE PHDBALL FACTORY ONLY
    #WORK WITH SINGLE PHDBALL FILE
    #TODO - FIX THIS IN PHDBALL FACTORY
    unless ($self->_gather_phd_data) {
	$self->error_message("Could not gather phd data");
	return;
    }

    #DS LINE IN 454 ACE FILES HAS TO HAVE PHD_FILE: TRACE_NAME TO WORK W CONTIGTOOLS
    #THIS CREATES A NEW ACE FILE: $ace_in.DS_Line_fixed;
    #TODO - FIX THIS IN CONTIG TOOLS
    my $new_ace;
    unless ($new_ace = $self->_add_phd_to_ace_DS_line ($self->ace)) {
	$self->error_message("Cound not add PHD_FILE: READ_NAME to ace DS line");
	return;
    }

    #LOAD ACE OBJECT
    my ($ace_obj, $contig_tool);
    unless (($ace_obj, $contig_tool) = $self->_load_ace_obj ($new_ace)) {
	$self->error_message("Unable to load ace object");
	return;
    }

    #GET GENERAL CONTIG INFO
    my $scaffolds;
    unless ($scaffolds = $self->_get_scaffold_info ($ace_obj)) {
	$self->error_message("Could not get contig info from ace");
	return;
    }

    #PRINT CONTIG END SEQUENCES TO RUN CROSS MATCH
    unless ($self->_print_contig_ends ($ace_obj, $scaffolds)) {
	$self->error_message("Could not print contig ends for cross_match");
	return;
    }

    #RUN CROSS MATCH
    unless ($self->_run_cross_match) {
	$self->error_message("Could not run cross_match");
	return;
    }

    my $cm_aligns = {};
    unless ($cm_aligns = $self->parse_cross_match_outfile()) {
	$self->error_message("generic parse cross_match failed");
	return;
    }

    return $cm_aligns, $ace_obj, $contig_tool, $scaffolds;
}

sub _gather_phd_data
{
    my ($self) = @_;

    my $phdball_dir = '../phdball_dir';

    return 1 if ! -d $phdball_dir;

    my $autojoin_ball_name = 'autoJoinPhdBall';

    return 1 if -s $phdball_dir.'/'.$autojoin_ball_name;

    if (-d $phdball_dir)
    {
        my @ball_files = glob ("$phdball_dir/*");

        if (scalar @ball_files > 0)
        {
            foreach my $ball_file (@ball_files)
            {
                my $ec = `cat $ball_file >> $phdball_dir/autoJoinPhdBall`;
                $self->error_message ("Cannot cat $ball_file to autoJoinPhdBall") and
		    return if $ec;
            }
        }
    }

    return 1;
}


sub _add_phd_to_ace_DS_line
{
    my ($self, $ace) = @_;

    my $ace_out = $ace.'.DS_line_fixed';
    return unless my $fh = IO::File->new("< $ace");
    return unless my $out_fh = IO::File->new("> $ace_out");

    my $read_name;
    while (my $line = $fh->getline)
    {
        if ($line =~ /^RD\s+/)
        {
            ($read_name) = $line =~ /^RD\s+(\S+)/;
            $out_fh->print($line);
            next;
        }
        if ($line =~ /^DS\s+/)
        {
            if ($line =~ /PHD_FILE\:\s+/)
            {
                $out_fh->print($line);
                next;
            }
            chomp $line;
            $line .= " PHD_FILE: $read_name\n";
            $out_fh->print($line);
            next;
        }
        $out_fh->print($line);
    }

    $fh->close;
    $out_fh->close;
    return $ace_out;
}

sub _load_ace_obj
{
    my ($self, $ace) = @_;

    my $tool = Finishing::Assembly::ContigTools->new;

    my $fo = Finishing::Assembly::Factory->connect('ace', $ace);

    return $fo->get_assembly, $tool;
}

sub _get_scaffold_info
{
    my ($self, $ace_obj) = @_;

    my ($contigs, $list) = $self->_get_contigs_info ($ace_obj);

    my $contigs_with_scaffolds = $self->_add_scaffolding_info ($contigs, $list);

    return $contigs_with_scaffolds;
}

sub _get_contigs_info
{
    my ($self, $ace_obj) = @_;

    my $contigs = {};

    my $contigs_list = [];

    foreach my $contig ($ace_obj->contigs->all)
    {
	my $reads_count = scalar $contig->assembled_reads->all;
	my $contig_length = $contig->unpadded_length;
	my $name = $contig->name;
	my ($contig_number) = $name =~ /^Contig(\S+)$/i;

	$contigs->{$contig_number}->{name} = $name;
	$contigs->{$contig_number}->{length} = $contig_length;
	$contigs->{$contig_number}->{number_of_reads} = $reads_count;

	push @$contigs_list, $contig_number;
    }

    return $contigs, $contigs_list;
}

sub _add_scaffolding_info
{
    my ($self, $h, $ar) = @_;

    foreach my $ctg (nsort keys %$h)
    {
        next unless $ctg =~ /^\d+\.\d+$/;

        my $scaf = $ctg;
        $scaf =~ s/\.\d+$//;

        #pattern match each contig. to find all contigs
        #in each scaffold

        my (@scafs) = grep (/^$scaf\.\d+$/, @$ar);

        #don't hold scaffold contigs if contig
        #is not part of a scaffold

        next unless scalar @scafs > 1;

        @{$h->{$ctg}->{scaffolds}} = @scafs if @scafs;
    }

    return $h;
}

sub _print_contig_ends
{
    my ($self, $ao, $scaf_contigs) = @_;

    my $fasta_length = $self->cm_fasta_length;

    my $fasta_file = 'AutoJoin_CM_fasta';

    unlink $fasta_file if -s $fasta_file;

    my $fh = IO::File->new(">> $fasta_file");

    $self->error_message("Can not create file handle for cross_match fasta") and
	return unless $fh;

    my $merge_type = $self->merge_type;

    foreach my $contig ($ao->contigs->all)
    {
	my $name = $contig->name;
	my $number = $name;
	$number =~ s/^contig//i;

	my $fasta = $contig->unpadded_base_string;
	my $length = $contig->unpadded_length;

	#PARAMETERS SPECIFIC FOR 
	if ($merge_type eq 'ByCrossMatch') {
	    #IGNORE CONTIGS LESS THAN THIS LENGTH
	    if ($self->min_length) {
		next if $length < $self->min_length;
	    }
	    #IGNORE CONTIGS GREATHER THAN THIS LENGTH
	    if ($self->max_length) {
		next if $length > $self->max_length;
	    }
	    #IGNORE CONTIGS WITH LESS THAN THIS NUMBER OF READS
	    if ($self->min_read_num) {
		my $reads = $contig->assembled_reads;
		my $read_count = $reads->all;
		next if $read_count < $self->min_read_num;
	    }
	}
	else {
	    #ONLY INCLUDE CONTIGS THAT ARE A PART OF SCAFFOLD
	    next unless exists $scaf_contigs->{$number}->{scaffolds};
	}

	my ($left_end, $right_end);

	$fasta_length = $length if $length < $fasta_length;

	($left_end) = $fasta =~ /^(\w{$fasta_length})/;
	($right_end) = $fasta =~ /(\w{$fasta_length})$/;

	$fh->print(">$name"."-left\n"."$left_end\n");
	$fh->print(">$name"."-right\n"."$right_end\n");
    }

    $fh->close;

    #JUST MAKE SURE SOMETHING PRINTED
    $self->error_message("$fasta_file is blank or missing") and
	return unless -s $fasta_file;

    return 1;
}

sub _run_cross_match
{
    my ($self) = @_;

    my $min_match = $self->cm_min_match;

    my $fasta_file = 'AutoJoin_CM_fasta';

    unless (-s $fasta_file)
    {
	$self->error_message ("cross_match input fasta is missing");
	return;
    }

    my $cm_out_file = 'AutoJoin_CM_fasta_out';

    unlink $cm_out_file if -s $cm_out_file;

    my $ec = system ("cross_match $fasta_file -minmatch $min_match -masklevel 101 > $cm_out_file");

    if ($ec)
    {
	$self->error_message("cross_match failed to run");
	return;
    }

    return 1;
}

sub clean_up_merged_ace
{
    my ($self, $merged_ace) = @_;

    #NEED TO FIX THE DS LINE HERE TO MAKE IT WORK FOR 454 DATA
    my $ds_fixed_ace = $self->_add_version_to_DS_line ($merged_ace);

    #REMOVE AUTOJOIN PHD FILE
    unlink '../phdball_dir/autoJoinPhdBall';

    #NEED TO APPEND ACE FILE WITH WA TAGS TO MAKE TRACES VIEWABLE
    my $done = $self->_add_WA_tags_to_ace ($ds_fixed_ace);

    #REMOVE SOME INTERMEDIATE ACE FILES
    unlink $merged_ace;

    return 1;
}

sub _add_version_to_DS_line
{
    my ($self, $ace) = @_;

    my $ace_out = $ace.'.final';

    my $fh = IO::File->new("< $ace")
	or die "Cannot open file: $ace";

    my $out_fh = IO::File->new (">$ace_out")
	or die "Cannot create file handle: $ace_out";

    while (my $line = $fh->getline)
    {
        if ($line =~ /^DS\s+/)
        {
            chomp $line;
            if ($line =~ /\.sff\:/ and $line =~ /PHD_FILE\:\s+\S+/)
            {
                $line =~ s/^DS /DS VERSION: 1 /;
                $line =~ s/PHD_FILE\:\s+\S+\s+//;
                $line .= ' CHEM: 454';
                $out_fh->print($line."\n");
                next;
            }
            $out_fh->print($line."\n");
            next;
        }
        $out_fh->print($line);
    }
    $fh->close;

    $out_fh->close;

    return $ace_out;
}

sub _add_WA_tags_to_ace
{
    my ($self, $ace) = @_;

    my $fh = IO::File->new(">> $ace")
	or die "Cannot create filehandle for $ace";

    my $ball_dir = '../phdball_dir';

    if (-d $ball_dir)
    {
        my @phdball_files = glob ("$ball_dir/*");
        if (scalar @phdball_files > 0)
        {
            chomp (my $date = `date '+%y%m%d:%H%M%S'`);

            foreach my $ball_file (@phdball_files)
            {
                my $tag = "\nWA{\nphdBall newbler $date\n$ball_file\n}\n";
                $fh->print($tag);
            }
        }
    }
    $fh->close;

    return 1;
}

#TODO - THIS SHOULD PRINT TO A FILE
sub print_report
{
    my ($self, $new_scaffolds) = @_;

    $self->error_message ("No new scaffolds found") and return
	unless scalar @$new_scaffolds > 0;
    my $joins_count = 0;

    foreach my $scaffold (@$new_scaffolds) {

	my ($new_contig_name) = $scaffold =~ /New\s+scaffold\:\s+(\S+)/;
	$new_contig_name = 'Contig'.$new_contig_name;

	$scaffold =~ s/New\s+scaffold\:\s+\S+//;

	my @tmp = split (/\s+/, $scaffold);

	my $scaffold_string;

	foreach (@tmp) {
	    $_ =~ s/^\s+//;

	    next unless $_ =~ /^\S+/;

	    if ($_ =~ /\<\-\d+\-\>/) {
		$scaffold_string .= $_.' ';
		$joins_count++;
	    }
	    elsif ($_ =~ /\(\S+\)/) {
		my ($contig_number) = $_ =~ /\((\S+)\)/;
		$scaffold_string .= '('.'Contig'.$contig_number.')'.' ';
	    }
	    else {
		$scaffold_string .= 'Contig'.$_.' ';
	    }
	}

	$scaffold_string =~ s/\s+$//;
	print $new_contig_name.'  =>  '.$scaffold_string."\n";
    }
    print "Total number of joins: $joins_count\n";
    return 1;
}

sub parse_cross_match_outfile
{
    my ($self) = @_;
    my $reader = Alignment::Crossmatch::Reader->new(io => 'AutoJoin_CM_fasta_out');
    my @alignments = $reader->all;

    my $aligns = {};

    #TODO - THESE SHOULD BE TWO SEPARATE METHODS
    
    foreach (@alignments) {
	#NAMES LOOK LIKE THIS Contig0.1-right
	my $query_name = $_->{query_name};
	my ($query_contig, $query_dir) = $query_name =~ /(\S+)\-(right|left)/;
	my $subject_name = $_->{subject_name};
	my ($subject_contig, $subject_dir) = $subject_name =~ /(\S+)\-(right|left)/;

	#IGNORE INTRA CONTIG HITS;
	next if $query_contig eq $subject_contig;

	#FIGURE OUT IF SUBJECT IS COMPLEMENTED OR NOT
	#IF SUBJECT START IS GREATER THAN SUBJECT STOP, IT'S COMPELMENTED
         	#DOES THIS MATTER??
	#TODO - WHAT HAPPENS IF CONTIG-RIGHT HITS CONTIG-RIGHT

	my $query_start = $_->{query_start};
	my $query_end = $_->{query_stop};
	my $subject_start = $_->{subject_start};
	my $subject_end = $_->{subject_stop};

	my $u_or_c = ($subject_start > $subject_end) ? 'C' : 'U';

	#IF SUBJECT AND QUERY MATCH SAME ENDS, IE, BOTH RIGHT OR LEFT,
	#THEN SEQUENCE MATCH MUST BE COMPELEMTED RELATIVE TO EACH OTHER

	if ($subject_dir eq $query_dir) {
	    next unless $u_or_c eq 'C';
	}
	else {
	    next unless $u_or_c eq 'U';
	}

	my $bases_overlap = ($subject_start > $subject_end) ? $subject_start - $subject_end : $subject_end - $subject_start;

#DON'T NEED THIS FOR NOW
#	$aligns->{$query_contig}->{$query_dir}->{$subject_contig}->{subject_start} = $subject_start;
#	$aligns->{$query_contig}->{$query_dir}->{$subject_contig}->{subject_end} = $subject_end;
#	$aligns->{$query_contig}->{$query_dir}->{$subject_contig}->{query_start} = $query_start;
#	$aligns->{$query_contig}->{$query_dir}->{$subject_contig}->{query_end} = $query_end;
	$aligns->{$query_contig}->{$query_dir}->{$subject_contig}->{u_or_c} = $u_or_c;
	$aligns->{$query_contig}->{$query_dir}->{$subject_contig}->{l_or_r} = $subject_dir;
	$aligns->{$query_contig}->{$query_dir}->{$subject_contig}->{bases_overlap} = $bases_overlap;
    }
    return $aligns;
}

sub make_joins
{
    my ($self, $scafs, $ace_obj, $ctg_tool) = @_;

    my $dir = cwd();

    print "Please wait: gathering phds and ace file .. this could take up to 10 minutes\n";

    my $ace_out = $self->ace.'.autojoined';

    my $xport = Finishing::Assembly::Ace::Exporter->new( file => $ace_out );

    my @phd_objs;

    my $phd_dir = "$dir/../phd_dir";

    if (-d $phd_dir)
    {
	my $phd_obj = Finishing::Assembly::Phd->new(input_directory => "$phd_dir");

	unless ($phd_obj)
	{
	    $self->error_message("Unable to create phd_dir object");
	    return;
	}

	push @phd_objs, $phd_obj;
    }

    my $phd_ball = "$dir/../phdball_dir/autoJoinPhdBall";

    if (-s $phd_ball)
    {
        my $phd_ball_obj = Finishing::Assembly::Phd::Ball->connect(ball => $phd_ball);

	unless ($phd_ball_obj)
	{
	    $self->error_message("Unable to create phdball object");
	    return;
	}

        push @phd_objs, $phd_ball_obj;
    }

    unless (scalar @phd_objs > 0)
    {
	$self->error_message("No phd objects were loaded");
	return;
    }

    #create a temp hash to keep track of contigs not joined
    my %unused_contig_names;
    foreach ($ace_obj->contigs->all)
    {
        $unused_contig_names{$_->name} = 1;
    }

    my $join_count = 0;
    my $ace_version = 0;
    my $last_merge_failed = 0;

    foreach my $line (@$scafs)
    {
        #new scaf number?
        #scaffold name is really the first contig name

        my ($new_scaf_name) = $line =~ /^New\s+scaffold:\s+(\d+\.\d+)/;
        $new_scaf_name = 'Contig'.$new_scaf_name;

        $line =~ s/^New\s+scaffold:\s+(\d+\.\d+)\s+//; #GET RID OF THIS
        my @ctgs = split (/\s+\<-\d+-\>\s+/, $line);

        my $next_ctg = shift @ctgs;

        #accepts (1.1) or 1.1 and returns the following
        #Contig1.1, yes for (1.1) and
        #Contig1.1, no for 1.1

        my ($left_ctg_name, $left_comp) = $self->_resolve_complementation ($next_ctg);

        my $left_ctg_obj;

	unless ($left_ctg_obj = $ace_obj->get_contig ($left_ctg_name)) {

	    $self->error_message("Unable to get contig object for $left_ctg_name");
	    return;
	}

	if ($left_comp eq 'yes') {

	    unless ($left_ctg_obj->complement) {

		$self->error_message("Unable to complement contig: $left_ctg_name");
		return;
	    }
	}

        while (scalar @ctgs > 0) {

            $next_ctg = shift @ctgs;
            my ($right_ctg_name, $right_comp) = $self->_resolve_complementation ($next_ctg);

	    #NEED TO RE DEFINE LEFT CONTIG NAME HERE

	    my $left_contig_name = $left_ctg_obj->name;
	    print "Trying to merge $left_contig_name to $right_ctg_name\n";

            my $right_ctg_obj;

	    unless ($right_ctg_obj = $ace_obj->get_contig($right_ctg_name)) {

		$self->error_message("Unable to get contig_obj: $right_ctg_name");
		return;
	    }

	    if ($right_comp eq 'yes') {

		unless ($right_ctg_obj->complement) {

		    $self->error_message("Unable to complement contig: $right_ctg_name");
		    return;
		}
	    }

            eval {
                $left_ctg_obj = $ctg_tool->merge($left_ctg_obj, $right_ctg_obj, undef, phd_array => \@phd_objs);
            };

            if ($@) {
		$last_merge_failed = 1;
		#MERGE FAILED SO EXPORT THE LEFT CONTIG
		print " => Merge failed! \n\tExporting $left_contig_name\n";

		#IT LOOKS LIKE THERE ARE PROBLEMS WITH CONTIG OBJECTS
		#WHEN MERGE FAILS .. SO GET A NEW CONTIG OBJECT

		$left_ctg_obj = $ace_obj->get_contig ($left_ctg_name);

		$xport->export_contig(contig => $left_ctg_obj);

		print "Finished exporting ".$left_ctg_obj->name."\n";

		#REMOVE IT FROM LIST OF CONTIGS THAT WILL LATER ALL BE EXPORTED
		delete $unused_contig_names{$left_ctg_name} if
		    exists $unused_contig_names{$left_ctg_name};
		print "The real right contig name".$right_ctg_obj->name."\n";
		#IF RIGHT CONTIG WAS THE LAST CONTIG IN SCAFFOLD JUST EXPORT THAT TOO
		if (scalar @ctgs == 0) {
		    print "\tExporting $right_ctg_name too\n\tIt's the last contig in scaffold\n";

		    $right_ctg_obj = $ace_obj->get_contig ($right_ctg_name);

		    $xport->export_contig(contig => $right_ctg_obj);
		    delete $unused_contig_names{$right_ctg_name} if
			exists $unused_contig_names{$right_ctg_name};
		    next;
		}

		#MAKE THE RIGHT CONTIG OBJECT THE LEFT CONTIG OBJECT
		print "\tMaking $right_ctg_name left contig to continue merging\n";

		$left_ctg_obj = $right_ctg_obj;
		$left_ctg_name = $left_ctg_obj->name;

		#CONTINUE TO MERGE USING RIGHT CONTIG AS THE NEXT LEFT CONTIG
		next;
            }
	    else {
		print " => Successfully merged $left_ctg_name to $right_ctg_name\n";
		$last_merge_failed = 0;
	    }

	    #TODO CREATE LOG FILE THAT LISTS ALL THE JOINS

            foreach ($left_ctg_name, $right_ctg_name) {
                delete $unused_contig_names{$_} if exists $unused_contig_names{$_};
            }
        }

	unless ($last_merge_failed == 1) {

	    $xport->export_contig(contig => $left_ctg_obj, new_name => $left_ctg_name);
	}
    }

    #need to export all the unused contigs
    if (scalar keys %unused_contig_names > 0) {

#	print "Exporting unmerged contigs\n";
        foreach (keys %unused_contig_names) {

            my $contig_obj = $ace_obj->get_contig($_);
#	    print "\t".$contig_obj->name."\n";
	    $xport->export_contig(contig => $contig_obj);
        }
    }

    $xport->close;

    return $ace_out;
}

sub _resolve_complementation
{
    my ($self, $contig_number) = @_;
    return 'Contig'.$contig_number, 'no' unless $contig_number =~ /\(\S+\)/;
    ($contig_number) = $contig_number =~ /\((\S+)\)/;
    return 'Contig'.$contig_number, 'yes';
}

sub create_test_temp_dir
{
    my ($self, $dir) = @_;

    unless (-d $dir) {
	$self->error_message("Unable to access test directory: $dir");
	return;
    }

    chdir ($dir);
    mkdir ("$dir/edit_dir");

    my $test_root_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Assembly-AutoJoin';

    eval {
	symlink $test_root_dir.'/phd_dir', "$dir/phd_dir";
    };
    if ($@) {
	$self->error_message("Unable to create link to test phd_dir");
	return;
    };

    eval {
	symlink $test_root_dir.'/phdball_dir', "$dir/phdball_dir";
    };
    if ($@) {
	$self->error_message("Unable to create link to test phdball_dir");
	return;
    };

    eval {
	symlink $test_root_dir.'/sff_dir', "$dir/sff_dir";
    };
    if ($@) {
	$self->error_message("Unable to create link to test sff_dir");
	return;
    };

    eval {
	symlink $test_root_dir.'/edit_dir/autojoin_test.ace', "$dir/edit_dir/autojoin_test.ace";
    };
    if ($@) {
	$self->error_message("Unable to create link to test ace");
	return;
    };
    return 1;
}

sub merge_type {
    my ($self) = @_;
    my ($merge_type) = ref($self) =~ /(\w+)$/;
    return $merge_type;
}

1;
