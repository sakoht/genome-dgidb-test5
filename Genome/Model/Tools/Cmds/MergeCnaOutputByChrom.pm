package Genome::Model::Tools::Cmds::MergeCnaOutputByChrom;

use strict;
use warnings;
use Genome;
use IO::File;
use Statistics::Descriptive;
use List::Util "min","max";

class Genome::Model::Tools::Cmds::MergeCnaOutputByChrom {
    is => 'Command',
    has => [
    bam_to_cna_output_files => {
        type => 'Single-quoted String',
        is_optional => 0,
        doc => "A single-quoted string describing the names of copy_number_output.out files, or all the links to these files created by tool gmt cmds compile-cna-output. Example: '/dir/*.out'",
    },
    output_filename => {
        type => 'String',
        is_optional => 0,
        doc => 'Filename of merged data from all input files for usage in CMDS analysis. 1 file is printed per chromosome with name "output_file.1", for example.',
    },
    ]
};

sub help_brief {
    'Create per-chromosome files from many bam-to-cna files'
}

sub help_detail {
    "This script reads the bam-to-cna outputs of many samples and compiles all of the data from the DIFF columns into a single file (per chromosome) for input into the cmds.R function."
}

sub execute {
    my $self = shift;
    $DB::single=1;

    #process input arguments
    my $outfile = $self->output_filename;
    my $output_fh = new IO::File;
    my @infiles = glob($self->bam_to_cna_output_files);
    chomp @infiles;
    @infiles = sort @infiles; #so that the files are always read and printed in the same order

    #make sure --bam-to-cna-output-files were quoted SOMEONE TOOK MY BARE-ARGS AWAY
    #if (scalar @{$self->bare_args}) {
    #    my @bare_args = @{$self->bare_args};
    #    die "\nDid you forget to quote the --bam-to-cna-output-files? I found these extra arguments in your call:\n@bare_args\n";
    #}
    
    my %data;
    my %chr_to_index;
    my %index_to_chr;
    my $chr_to_index = \%chr_to_index;
    my $index_to_chr = \%index_to_chr;
    my $data = \%data;
    ($chr_to_index,$index_to_chr) = fill_chr_hashes($chr_to_index,$index_to_chr); #these hashes index the chr list so that the order can be known between numbers and MT,X,Y
    my $prev_cur_max_chr = 0; #this ensures a new file is opened for writing at the first chromosome


    #Create data hash, including input filehandles
    for my $file (@infiles) {
        my $filehandle = IO::File->new($file,"r");
        $data{$file}{"filehandle"} = $filehandle;
    }

    #create header row to be used throughout
    my $header = "CHR\tPOS";
    for my $filename (@infiles) {
        (my $col_id = $filename) =~ s/^(\w+)\.copy.+/$1/;
        $header .= "\t$col_id";
    }
    $header .= "\n";

    #populate hashes with first line of data
    for my $file (@infiles) {
        ($data) = $self->read_row_of_data($file,$data);
    }

    #Print data
    MASTER: while (1) {
        #find max chr (since all have to match)
        my @cur_chr_indexes = ();
        for my $file (@infiles) {
            push @cur_chr_indexes, $chr_to_index{ $data{$file}{"cur_chr"} };
        }
        my $cur_max_chr_index = max @cur_chr_indexes;
        my $cur_max_chr = $index_to_chr{$cur_max_chr_index};

        #read data until all files are at max chr
        for my $file (@infiles) {
            while ($data{$file}{"cur_chr"} ne $cur_max_chr) {
                ($data) = $self->read_row_of_data($file,$data);;
                next MASTER if ($chr_to_index{$data{$file}{"cur_chr"}} > $cur_max_chr_index);
            }
        }

        #find max pos
        my @cur_pos = ();
        for my $file (@infiles) {
            push @cur_pos, $data{$file}{"cur_pos"};
        }
        my $cur_max_pos = max @cur_pos;

        #read data until all files are now also at max position
        for my $file (@infiles) {
            while ($data{$file}{"cur_pos"} ne $cur_max_pos) {
                ($data) = $self->read_row_of_data($file,$data);;
                next MASTER if ($chr_to_index{$data{$file}{"cur_chr"}} > $cur_max_chr_index);
                next MASTER if ($data{$file}{"cur_pos"} > $cur_max_pos);
            }
        }

        #if we have switched chromosomes, open a new output file and close the old output file
        if (defined($prev_cur_max_chr) && $cur_max_chr ne $prev_cur_max_chr) {
            $output_fh->close;
            $output_fh = open_new_output_fh($outfile,$header,$cur_max_chr);
            $prev_cur_max_chr = $cur_max_chr;
        }

#write a row of data
        $output_fh->print("$cur_max_chr\t$cur_max_pos");
        for my $file (@infiles) {
            my $cur_chr_this_file = $data{$file}{"cur_chr"};
            my $cur_pos_this_file = $data{$file}{"cur_pos"};
            #if the file has output at this chr & pos, print results
            if ($cur_chr_this_file eq $cur_max_chr) {
                if ($cur_pos_this_file eq $cur_max_pos) {
                    $output_fh->print("\t$data{$file}{'cur_data'}");
                    unless ($data->{$file}{"eof"}) {
                        ($data) = $self->read_row_of_data($file,$data);
                    }
                    if ($file eq $infiles[$#infiles] && $data->{$file}{"eof"}) {
                        $output_fh->print("\n");
                        $self->status_message("Reached the end of all files.");
                        return;
                    }
                }
                else {
                    die "some problem occured - there's no data where it was supposedly matched above";
                }
            }
        }
        $output_fh->print("\n");
    }

#Close all filehandles
    for my $file (@infiles) {
        $data{$file}{"filehandle"}->close;
    }
    $output_fh->close;

    return 1;
}

#sub to open output filehandle and print headers
sub open_new_output_fh {
    my $outfile = shift;
    my $header = shift;
    my $chr = shift;
    my $output_filename = $outfile.".".$chr;
    my $output_fh = new IO::File $output_filename,"w";
    $output_fh->print($header);
    return $output_fh;
}

sub fill_chr_hashes {
    my $chr_to_index = shift;
    my $index_to_chr = shift;
    my @chr_list = (1..22,"X");
    my $index = 1;
    for my $chr (@chr_list) {
        $chr_to_index->{$chr} = $index;
        $index_to_chr->{$index} = $chr;
        $index++;
    }
    $chr_to_index->{"eof"} = $index;
    $index_to_chr->{$index} = "eof";
    return ($chr_to_index,$index_to_chr);
}

sub read_row_of_data {
    my ($self,$file,$data) = @_;
    if (exists $data->{$file}{"eof"} && $data->{$file}{"eof"} == 1) {
        $self->error_message("Reached the end of $file.");
        return;
    }
    
    my $line = $data->{$file}{"filehandle"}->getline;

    #ignore header info
    while ($line =~ /^#|^CHR/) {
        $line = $data->{$file}{"filehandle"}->getline;
    }

    chomp $line;
    (my $chr, my $pos, my $tumor, my $normal, my $diff) = split /\t/,$line;
    $data->{$file}{"cur_chr"} = $chr;
    $data->{$file}{"cur_pos"} = $pos;
    $data->{$file}{"cur_data"} = $diff;
    $data->{$file}{"eof"} = $data->{$file}{"filehandle"}->eof;
    return ($data);
}
1;
