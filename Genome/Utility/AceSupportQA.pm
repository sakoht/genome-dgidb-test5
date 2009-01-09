package Genome::Utility::AceSupportQA;

use strict;
use warnings;
use Benchmark;
use DBI;

#Generate a refseq;
use Bio::DB::Fasta;
my $RefDir = "/gscmnt/sata180/info/medseq/biodb/shared/Hs_build36_mask1c/";
my $refdb = Bio::DB::Fasta->new($RefDir); #$refdb is the entire Hs_build36_mask1c 

###MODIFIED so that it doesn't fix anything 
my $fix_invalid_files;

sub ace_support_qa {
    my $class = shift;
    my $ace_file = shift; ##Give full path to ace file including ace file name

    my $t0 = new Benchmark;

    
    unless (-s $ace_file) {
        warn "Ace file $ace_file does not exist";
        return;
    }
    
    #invalid_files will be a hash of trace names and file type that are broken.
    my ($invalid_files,$project) = &parse_ace_file($ace_file); ##QA the read dump, phred and poly files

    my ($refcheck) = &check_ref($project);
    unless ($refcheck) { 
        print qq(The reference sequence was not checked for correctness\n);
    }

    my $run;
    if ($invalid_files) {
        if ($refcheck =~ /Sequence doesn\'t look good/) {
            $run = qq(The reference sequence as well as some of the trace files are invalid for $project and should be fixed prior to analysis\n);
        } else {
            $run = qq(There are invalid files for $project that should be fixed prior to analysis\n);
        }
        print qq(Here is a list of reads for $project with either a broken chromat, phd, or poly file\n);
        foreach my $read (sort keys %{$invalid_files}) {
            print "$read";
            foreach my $file_type (sort keys %{$invalid_files->{$read}}) {
                print "\t$file_type";
            }
            print "\n";
        }
    } else {

        if ($refcheck =~ /Sequence doesn\'t look good/) {
            $run = qq(The reference sequence is invalid for $project and should be fixed prior to analysis\n);
        } else {
            $run = 1;
        }
    }

    my $t1 = new Benchmark;
    my $td = timediff($t1, $t0);
    print "the code took:",timestr($td),"\n";

    if ($run) {
        return ($run);
    }
}

sub check_ref {
    my ($assembly_name) = @_;
    my $amplicon_tag = GSC::AssemblyProject->get_reference_tag(assembly_project_name => $assembly_name);

    unless($amplicon_tag){
        warn "no amplicon tag from GSC::AssemblyProject->get_reference_tag(assembly_project_name => $assembly_name)... can't check the reference sequence";
        return undef;
    }
    
    my $amplicon = $amplicon_tag->ref_id;
    my ($chromosome) = $amplicon_tag->sequence_item_name =~ /chrom([\S]+)\./;

    my $amplicon_sequence = $amplicon_tag->sequence_base_string;
    my $amplicon_offset = $amplicon_tag->begin_position;

    my $amplicon_begin = $amplicon_tag->begin_position;
    my $amplicon_end = $amplicon_tag->end_position;

    my $assembly_length = length($amplicon_sequence);
    my $strand = $amplicon_tag->strand;

    my ($start,$stop) = sort ($amplicon_begin,$amplicon_end);
    my $length = $stop - $start + 1;

    unless ($assembly_length == $length) { 
        print qq(the assembly_length doesn\'t jive with the spread on the coordinates\n); 
    }

    my $sequence = &get_ref_base($chromosome,$start,$stop); ##this will come reverse complemented if the $strand eq "-"
    if ($strand eq "-") {
        my $revseq = &reverse_complement_sequence ($sequence); 
        $sequence = $revseq;
    }
    my $result;
    if ($sequence eq $amplicon_sequence) { 
        $result = qq($assembly_name Sequence looks good.\n);
    } else {
        $result = qq($assembly_name Sequence doesn\'t look good.\n);
    }
    return $result;
}


sub get_ref_base {
    my ($chr_name,$chr_start,$chr_stop) = @_;
    my $seq = $refdb->seq($chr_name, $chr_start => $chr_stop);
    $seq =~ s/([\S]+)/\U$1/;
    return $seq;

}

sub reverse_complement_sequence {
    my ($seq) = @_;
    my $seq_1 = new Bio::Seq(-seq => $seq);
    my $revseq_1 = $seq_1->revcom();
    my $revseq = $revseq_1->seq;

    return $revseq;
}

sub parse_ace_file {
    my ($ace_file) = @_;
    my ($traces_fof);

    my @da = split(/\//,$ace_file);
    my $ace_name = pop(@da);

    my $edit_dir = join'/',@da;

    pop(@da);
    my $project_dir = join'/',@da;
    my $project = pop(@da);

    my $chromat_dir = "$project_dir/chromat_dir";
    my $phd_dir = "$project_dir/phd_dir";
    my $poly_dir = "$project_dir/poly_dir";

    use GSC::IO::Assembly::Ace;
    my $ao = GSC::IO::Assembly::Ace->new(input_file => $ace_file);

    my $contig_count;
    foreach my $name (@{ $ao->get_contig_names }) {
        $contig_count++;
        my $contig = $ao->get_contig($name);
        foreach my $read_name (keys %{ $contig->reads }) {
            unless ($read_name =~ /(\S+\.c1)$/) {
                $traces_fof->{$read_name}=1;
            }
        }
    }

    unless ($contig_count == 1) {print qq($project Contig count is equal to $contig_count\n);}
    my ($invalid_files)=&check_traces_fof($edit_dir,$project_dir,$chromat_dir,$phd_dir,$poly_dir,$traces_fof,$ace_file);
    return ($invalid_files,$project);
}

sub check_traces_fof {
    my ($edit_dir,$project_dir,$chromat_dir,$phd_dir,$poly_dir,$traces_fof,$ace_file) = @_;

    my ($no_trace_file,$no_phd_file,$no_poly_file,$empty_trace_file,$empty_poly_file,$empty_phd_file,$ncntrl_reads,$read_count,$repaired_file);
    my ($trace_files_needed,$phd_files_needed,$poly_files_needed);

    foreach my $read (sort keys %{$traces_fof}) {
        $read_count++;

        if ($read =~ /^n\-cntrl/) {$ncntrl_reads++;}

        my $trace = "$chromat_dir/$read.gz";

        unless (-s $trace) {
            if ($fix_invalid_files) {
                system qq(read_dump -scf-gz $read --output-dir=$chromat_dir);
            }
            if (-s $trace) {
                $repaired_file++;
            } elsif (-e $trace) {
                $empty_trace_file++;
                $trace_files_needed->{$read}=1;
            } else {
                $no_trace_file++;
                $trace_files_needed->{$read}=1;
            }
        }

        my $poly = "$poly_dir/$read.poly";

        unless (-s $poly) {
            if (-e $poly) {
                $empty_poly_file++;
                $poly_files_needed->{$read}=1;
            } else {
                $no_poly_file++;
                $poly_files_needed->{$read}=1;
            }
        }
        
        my $phd = "$phd_dir/$read.phd.1";

        unless (-s $phd) {
            if (-e $phd) {
                $empty_phd_file++;
                $phd_files_needed->{$read}=1;
            } else {
                $no_phd_file++;
                $phd_files_needed->{$read}=1;
            }
        }
    }

    my $invalid_files;

    unless ($read_count) { die "There are no reads in the ace file to be analyzed\n"; }

    print qq(Reads for analysis ==> $read_count\n);


    if ($no_trace_file || $empty_trace_file) {

        unless($no_trace_file) {$no_trace_file=0;}
        unless($empty_trace_file) {$empty_trace_file=0;}

        my $n = $no_trace_file + $empty_trace_file;
        print qq(nonviable trace files ==> $n\n);
        foreach my $read (sort keys %{$trace_files_needed}) {
            if ($fix_invalid_files) {print qq(attempted redump of $read failed\n);}
            $invalid_files->{$read}->{trace}=1;
        }
    }

    if ($no_poly_file || $empty_poly_file) {
        if ($no_poly_file eq $read_count) {
            print qq(There are no poly files, they can be created in analysis\n);
        } else {

            unless($no_poly_file) {$no_poly_file=0;}
            unless($empty_poly_file) {$empty_poly_file=0;}

            my $n = $no_poly_file + $empty_poly_file;
            if ($fix_invalid_files) {print qq(will run phred to produce $n disfunctional poly files\n);}
            foreach my $read (sort keys %{$poly_files_needed}) {
                if ($trace_files_needed->{$read}) {
                    if ($fix_invalid_files) {
                        print qq(no attempt made to produce a poly file for $read as the trace file is missing\n);
                    }
                    $invalid_files->{$read}->{poly}=1;
                } else {
                    if ($fix_invalid_files) {system qq(phred -dd $poly_dir $chromat_dir/$read.gz);}
                    my $poly = "$poly_dir/$read.poly";

                    if (-s $poly) {
                        $repaired_file++;
                        print "poly file for $read ok\n";
                    }
                    else {
                        if ($fix_invalid_files) {
                            print qq(attempted to produce a poly file for $read failed\n);
                        }
                        $invalid_files->{$read}->{poly}=1;
                    }
                }
            }
        }
    }

    my ($check_phd_time_stamps);    
    if ($no_phd_file || $empty_phd_file) {

        unless($no_phd_file) {$no_phd_file=0;}
        unless($empty_phd_file) {$empty_phd_file=0;}

        my $n = $no_phd_file + $empty_phd_file;

        if ($fix_invalid_files) {print qq(will run phred to produce $n disfunctional phd files\n);}
        foreach my $read (sort keys %{$phd_files_needed}) {
            if ($trace_files_needed->{$read}) {
                if ($fix_invalid_files) {
                    print qq(no attempt made to produce a phd file for $read as the trace file is missing\n);
                }
                $invalid_files->{$read}->{phd}=1;
            } else {
                my $phd = "$phd_dir/$read.phd.1";

                if (-s $phd) {
                    $repaired_file++;
                } else {
                    $invalid_files->{$read}->{phd}=1;
                }
            }
        }
    }


    ##sync_phd_time_stamps is not working correctly. It didn't change the time stamp in the ace file
    if ($check_phd_time_stamps) {
        if ($fix_invalid_files) {
            print qq(will attempt to sync the phd file time stamps with the ace file\n);
            ($ace_file)=&sync_phd_time_stamps($ace_file);

            unless (-s $ace_file) {
                die "The synced ace file $ace_file doesnt exist or has zero size";
            }
        }
    }

    if ($ncntrl_reads) {
        print OUT qq(There were $ncntrl_reads n-cntrl reads\n);
    }

    return ($invalid_files);
}


sub sync_phd_time_stamps {   ## this isn't being used and it doesn't appear to do what it should

    #addapted from ~kkyung/bin/fix_autojoin_DS_line.pl

    use IO::File;
    use Data::Dumper;

    my ($ace) = @_;
    system qq(cp $ace $ace.presync);
    open(NEWACE,">$ace.synced");

    my $fh = IO::File->new("<$ace") || die "Can not open $ace";

    my $ds = {};

    while (my $line = $fh->getline)
    {
        if ($line =~ /^DS\s/)
        {
            my ($version) = $line =~ /VERSION:\s+(\d+)/;
            my ($chromat) = $line =~ /CHROMAT_FILE:\s+(\S+)/;
            my ($phd_file) = $line =~ /PHD_FILE:\s+(\S+)/;
            my ($time) = $line =~ /TIME:\s+(\w+\s+\w+\s+\d+\s+\d+\:\d+\:\d+\s+\d+)/;
            my ($chem) = $line =~ /CHEM:\s+(\S+)/;
            my ($dye) = $line =~ /DYE:\s+(\S+)/;
            my ($template) = $line =~ /TEMPLATE:\s+(\S+)/;
            my ($direction) = $line =~ /DIRECTION:\s+(\S+)/;

            $ds->{chromat_file} = (defined $chromat) ? $chromat : 'unknown';
            $ds->{version} = (defined $version) ? $version : 'unknown';
            $ds->{phd_file} = (defined $phd_file) ? $phd_file : 'unknown';
            $ds->{time} = (defined $time) ? $time : 'unknown';
            $ds->{chem} = (defined $chem) ? $chem : 'unknown';
            $ds->{dye} = (defined $dye) ? $dye : 'unknown';
            $ds->{template} = (defined $template) ? $template : 'unknown';
            $ds->{direction} = (defined $direction) ? $direction : 'unknown';
            $ds->{is_454} = ($chromat =~ /\.sff\:/) ? 'yes' : 'no';

            my $ds_line = 'DS ';
            if ($chromat =~ /\.sff\:/)
            {
                $ds_line .= 'VERSION: '.$ds->{version}.' ' unless $ds->{version} eq 'unknown';
            }
            $ds_line .= 'CHROMAT_FILE: '.$ds->{chromat_file}.' ';
            $ds_line .= 'PHD_FILE: '.$ds->{phd_file}.' ' unless $ds->{phd_file} eq 'unknown';
            $ds_line .= 'TIME: '.$ds->{time}.' ';
            $ds_line .= 'CHEM: '.$ds->{chem}.' ' unless $ds->{chem} eq 'unknown';
            $ds_line .= 'DYE: '.$ds->{dye}.' ' unless $ds->{dye} eq 'unknown';
            $ds_line .= 'TEMPLATE: '.$ds->{template}.' ' unless $ds->{template} eq 'unknown';
            $ds_line .= 'DIRECTION: '.$ds->{direction}.' ' unless $ds->{direction} eq 'unknown';

            $ds_line =~ s/\s+$//;

            print NEWACE $ds_line."\n";

        }
        else
        {
            print NEWACE $line;
        }
    }
    $fh->close;
    close(NEWACE);

    system qq(cp $ace.synced $ace);
    return($ace);
}

1;
