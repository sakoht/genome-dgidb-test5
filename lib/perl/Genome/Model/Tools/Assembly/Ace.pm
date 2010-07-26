package Genome::Model::Tools::Assembly::Ace;

use strict;
use warnings;

use Genome;
use IO::File;
use Data::Dumper;

class Genome::Model::Tools::Assembly::Ace {
    is => 'Command',
    has => [ ],
};

sub help_brief {
    'Tools to export or remove contigs in ace file'
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools assembly ace
EOS
}

sub xhelp_detail {
    return <<EOS
EOS
}
#validate contigs list and contig names in list
sub get_valid_contigs_from_list {
    my $self = shift;
    my $contigs_list = {}; #return a hash of contig names
    unless (-s $self->contigs_list) {
	$self->error_message("Failed to find list of contigs:".$self->contigs_list);
	return;
    }
    my $fh = IO::File->new("<".$self->contigs_list) ||
	die "Can not create file handle for list of contigs\n";
    while (my $line = $fh->getline) {
	next if $line =~ /^\s+$/;
	chomp $line;
	my @ar = split(/\s+/, $line); #Contig9.99 Contig10.1
	foreach (@ar) {
	    unless ($_ =~ /^contig\d+$/i or $_ =~ /^contig\d+\.\d+$/i) {
		$self->error_message("Contig names must be in this format: Contig4 Contig4.5\n\t".
				     "instead you have $_\n");
		return;
	    }
	    if (exists $contigs_list->{$_}) {
		$self->error_message("Warning: contig name: $_ is duplicated in list");
	    }
	    $contigs_list->{$_} = 1;
	}
    }
    $fh->close;
    return $contigs_list;
}
#validate ace files provided
sub get_valid_input_acefiles {
    my $self = shift;
    #validate ace input params
    unless ($self->ace or $self->ace_list or $self->acefile_names) {
	$self->error_message("ace or list of ace files must be supplied");
	return;
    }
    if ($self->ace and $self->ace_list and $self->acefile_names or $self->ace and $self->ace_list or $self->ace_list and $self->acefile_names or $self->ace and $self->acefile_names) {
	$self->error_message("You must supply either an ace file, list of ace files or a string of ace file names".
			     "and not all three of any combination of two");
	return;
    }
    my @acefiles;
    #check ace file
    if ($self->ace) {
	my $acefile = (-s $self->ace) ? $self->ace : $self->directory.'/'.$self->ace;
	unless (-s $acefile) {
	    $self->error_message("Can not find ace file or file is zero size: ".$acefile);
	    return;
	}
	push @acefiles, $acefile;
    }
    #check list of ace files
    if($self->ace_list) {
	unless (-s $self->ace_list) {
	    $self->error_message("Can not find ace list file or file is zero size: ".$self->ace_list);
	    return;
	}
	my $fh = IO::File->new("<".$self->ace_list) ||
	    die "Can not create file handle to read ace list: ".$self->ace_list."\n";
	while (my $line = $fh->getline) {
	    next if $line =~ /^\s+$/;
	    chomp $line;
	    my @ar = split(/\s+/, $line);
	    foreach (@ar) {
		my $acefile = (-s $_) ? $_ : $self->directory.'/'.$_;
		unless (-s $acefile) {
		    $self->error_message("Can not find ace file or file is zero size: ".$acefile);
		    return;
		}
		push @acefiles, $acefile;
	    }
	}
    }
    #check string of ace files
    if ($self->acefile_names) {
	my @files = $self->acefiles;
	foreach (@files) {
	    my $acefile = (-s $_) ? $_ : $self->directory.'/'.$_;
	    unless (-s $acefile) {
		$self->error_message("Can not find ace file or file is zero size: ".$acefile);
		return;
	    }
	    push @acefiles, $acefile;
	}
    }
    #validate ace file name
    foreach my $acefile (@acefiles) {
	unless ($acefile =~ /\.ace/) {
	    $self->error_message("Invalid file name for ace file: ".$acefile);
	    return;
	}
    }
    return \@acefiles;
}
#selectively print contig lines for exported contigs
sub filter_ace_files {
    my ($self, $acefiles, $contigs, $action) = @_;

    my @new_aces; #return ary ref of new ace names
    foreach my $acefile (@$acefiles) {
	my $ace_name = File::Basename::basename($acefile);
	my $int_file = $self->intermediate_file_name($ace_name);
	my $int_ace_fh = IO::File->new("> $int_file") ||
	    die "Can not create file handle for writing intmediate acefile\n";
	my $export_setting = 0; #set to print ace contents if == 1
	my $contig_count = 0;
	my $total_read_count = 0;
	my $fh = IO::File->new("< $acefile") ||
	    die "Can not create file handle to read $acefile\n";
	while (my $line = $fh->getline) {
	    #last if ($line =~ /^CT{/ or $line =~ /^WA{/);
	    next if $line =~ /^AS\s+/;
	    if ($line =~ /^CO\s+/) {
#		chomp $line;
		my $contig_name = $self->get_contig_name_from_ace_CO_line($line);
		if($action =~ /remove/) {
		    $export_setting = (exists $contigs->{$contig_name}) ? 0 : 1;
		}
		else {
		    $export_setting = (exists $contigs->{$contig_name}) ? 1 : 0;
		}
		#keep count of contigs and reads of those contigs that will be exported
		if ($export_setting == 1) {
		    my $read_count = $self->get_read_count_from_ace_CO_line($line);
		    $contig_count++;
		    $total_read_count += $read_count;
		}
	    }
	    last if ($line =~ /^CT{/ or $line =~ /^WA{/);
	    $int_ace_fh->print ($line) if $export_setting == 1;
	}
	$fh->close;
	$int_ace_fh->close;
	#re-write the ace file with correct contig and read counts
	my $ace_ext = ($action =~ /remove/) ? $ace_name.'.contigs_removed' : $ace_name.'.exported_contigs';
	my $final_ace;
	unless ($final_ace = $self->rewrite_ace_file($int_file, $contig_count, $total_read_count, $ace_ext)) {
	    $self->error_message("Failed to write final ace: $final_ace");
	    return;
	}
	unlink $int_file;
	push @new_aces, $final_ace;
    }
    return \@new_aces;
}
#cats multiple ace files together
sub merge_acefiles {
    my ($self, $acefiles) = @_;

    #print Dumper $acefiles;

    my $int_file = $self->intermediate_file_name('merge');
    my $int_fh = IO::File->new("> $int_file") ||
	die "Can not create file handle for $int_file";
    my $contig_count = 0;     my $read_count = 0;
    #incrementing contigs numbering by 1M for each acefile
    my $increment = 1000000;  my $inc_count = 0;
    foreach my $ace_in (@$acefiles) {
	my $fh = IO::File->new("< $ace_in") ||
	    die "Can not create file handle to read $ace_in\n";
	while (my $line = $fh->getline) {
	    #last if ($line =~ /^CT{/ or $line =~ /^WA{/); #reached end of contigs .. tags not transferred  
	    if ($line =~ /^AS\s+/) {
		chomp $line;
		my ($c1, $c2) = $self->get_counts_from_ace_AS_line($line);
		$contig_count += $c1;
		$read_count += $c2;
		next;
	    }
	    if ($line =~ /^CO\s+/) {
		chomp $line;
		my $contig_number = $self->get_contig_number_from_ace_CO_line($line);
		#need to rename contigs so there are no duplicate names
		#first ace file will retain same contig numbering
		#following ace files will have contig numbers incremented by 1,000,000
		#TODO - need intelligent way of doing this
		my $new_contig_number = ($increment * $inc_count) + $contig_number;
		$line =~ /^CO\s+(\S+)/; #just to capture $'
		$int_fh->print("CO Contig".$new_contig_number."$'"."\n");
		next;
	    }
	    last if ($line =~ /^CT{/ or $line =~ /^WA{/); #reached end of contigs .. tags not transferred
	    $int_fh->print($line);
	}
	$fh->close;
	$inc_count++;
    }
    $int_fh->close;
    #returns final ace name but not needed here
    unless ($self->rewrite_ace_file($int_file, $contig_count, $read_count, 'merged.final')){
	$self->error_message("Failed to write final ace file");
	return;
    }
    unlink $int_file;
    return 1;
}
#writes updated ace file with correct contig and read counts
sub rewrite_ace_file {
    my ($self, $ace_in, $contig_count, $read_count, $name) = @_;
    unless (-s $ace_in) {
	$self->error_message("Can't find int ace file or file is zero size: ".$ace_in);
	return;
    }

    #if final output is a single ace file, allow users to defined own final ace name
    my $ace_out;
    if ($self->ace) {
	$ace_out = ($self->ace_out) ? $self->ace_out : $self->directory.'/'.$name.'.ace';
    }
    else {
	$ace_out = $self->directory.'/'.$name.'.ace';
    }

    my $fh = IO::File->new("> $ace_out") ||
	die "Can not create file handle for final ace file\n";
    $fh->write("AS $contig_count $read_count\n\n");
    $fh->close;

    `cat $ace_in >> $ace_out`; #TODO - error check?/

    return $ace_out;
}
#get ace contig and read counts
sub get_counts_from_ace_AS_line {
    my ($self, $line) = @_;
    $line =~ /^AS\s+(\d+)\s+(\d+)/;
    my $contig_count = $1;
    my $read_count = $2;
    unless ($contig_count =~ /^\d+$/ and $read_count =~ /^\d+$/) {
	$self->error_message("Can't get contig and read counts from ace AS line: $line");
	return;
    }
    return $contig_count, $read_count;
}
#get read count from ace CO line
sub get_read_count_from_ace_CO_line {
    my ($self, $line) = @_;
    my ($read_count) = $line =~ /CO\s+\S+\s+\d+\s+(\d+)/;
    unless ($read_count and $read_count =~ /^\d+$/) {
	$self->error_message("Can't get read count from line: $line");
	return;
    }
    return $read_count;
}
#get contig name from ace CO line
sub get_contig_name_from_ace_CO_line {
    my ($self, $line) = @_;
    my ($contig_name) = $line =~ /CO\s+(\S+)\s+\d+\s+\d+/;
    unless ($contig_name) {
	$self->error_message("Can't get contig name from line: $line");
	return
    }
    return $contig_name;
}
#get contig number from ace CO lines
sub get_contig_number_from_ace_CO_line {
    my ($self, $line) = @_;
    my $contig_name = $self->get_contig_name_from_ace_CO_line($line);
    my ($contig_number) = $contig_name =~ /Contig(\S+)/i;
    unless ($contig_number =~ /^\d+$/ or $contig_number =~ /^\d+\.\d+$/) {
	$self->error_message("Can't get contig number from contig name: $contig_name".
			     "names should look like this: Contig4 or Contig 8.9");
	return;
    }
    #TODO - see what happens with Contig0 or Contig0.0 though these shouldn't exist
    return $contig_number;
}
#name for temp intermediate files that are not functional ace files
sub intermediate_file_name {
    my ($self, $name) = @_;

    return $self->directory.'/'.$name.'.intermediate';
}

1;
