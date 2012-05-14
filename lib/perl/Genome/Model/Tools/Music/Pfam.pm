package Genome::Model::Tools::Music::Pfam;

use warnings;
use strict;

use IO::File;
use Genome;
use IPC::Cmd qw/can_run/;

our $VERSION = $Genome::Model::Tools::Music::VERSION;

class Genome::Model::Tools::Music::Pfam {
    is => 'Genome::Model::Tools::Music::Base',
    has_input => [ 
        maf_file => {
            is => 'Text',
            is_input => 1,
            file_format => 'maf',
            doc => "List of mutations in MAF format",
        },
        output_file => {
            is => 'Text',
            is_output => 1,
            file_format => 'pfam',
            doc => "MAF file with Pfam domain column appended",
        },
       reference_build => {
           is => 'Text',
           doc => 'Options are \'Build36\' or \'Build37\'. This parameter ensures appropriate annotation of domains.',
           default => 'Build36',
       },
    ],
    doc => 'Add Pfam annotation to a MAF file.',
};

sub help_synopsis {
    return <<EOS
 ... music pfam \\
        --maf-file myMAF.tsv \\
        --output-file myMAF.tsv.pfam
EOS
}

sub help_detail {
    return <<EOS 
This command adds Pfam Domains to a column at the end of a MAF file.

This tool takes a MAF file, determines the location of each variant therein, and then uses a fast-lookup to retrieve all of the Pfam annotation domains that the variant crosses. A column is appended to the end of the input MAF file called "Pfam_Annotation_Domains" where the results are listed. "NA" is listed if no Pfam domains are found.
EOS
}

sub _doc_authors {
    return " Nathan D. Dees, Ph.D.";
}

sub _doc_credits {
    return <<EOS,
This tool uses tabix, by Heng Li.  See http://samtools.sourceforge.net/tabix.shtml.

This tool also depends on copies of data from the following databases, packaged in a form useable for quick analysis:

 * Pfam - http://pfam.sanger.ac.uk/
 * SMART - http://smart.embl-heidelberg.de/
 * SUPERFAMILY - http://supfam.cs.bris.ac.uk/SUPERFAMILY/
 * PatternScan - http://www.expasy.ch/prosite/
EOS
}

sub execute {

    #parse input arguments
    my $self = shift;
    my $maf_file = $self->maf_file;
    my $reference_build = $self->reference_build;
    my $output_file = $self->output_file;

    #open MAF file and output file
    my $maf_fh = new IO::File $maf_file,"r";
    my $out_fh = new IO::File $output_file,"w";

    #parse MAF header
    my $maf_header = $maf_fh->getline;
    while ($maf_header =~ /^#/) { 
        $out_fh->print($maf_header);
        $maf_header = $maf_fh->getline;
    }
    my %maf_columns;
    if ($maf_header =~ /Chromosome/) {
        chomp $maf_header;
        #header exists. determine columns containing gene name and sample name.
        my @header_fields = split /\t/,$maf_header;
        for (my $col_counter = 0; $col_counter <= $#header_fields; $col_counter++) {
            $maf_columns{$header_fields[$col_counter]} = $col_counter;
        }
        my $new_header = $maf_header . "\t" . "Pfam_Annotation_Domains" . "\n";
        $out_fh->print($new_header);
    }
    else {
        die "MAF does not seem to contain a header!\n";
    }

    #parse MAF variants and reprint file with domain column appended
    while (my $line = $maf_fh->getline) {

        #find position of variant
        chomp $line;
        my @fields = split /\t/,$line;
        my $chr = $fields[$maf_columns{'Chromosome'}];
        my $start = $fields[$maf_columns{'Start_position'}];
        my $stop = $fields[$maf_columns{'End_position'}];
        # use environment variable but fall back to reasonable default
        
        #formulate tabix command
        my $db_path = Genome::Sys->dbpath('pfam', 'latest') or die "Cannot find the pfam db path.";
        my $tabix = can_run('tabix') or die "Cannot find the tabix command. It can be obtained from http://sourceforge.net/projects/samtools/files/tabix";
        my $tabix_cmd = "$tabix";
        if ($reference_build eq 'Build36') {
            $tabix_cmd .= " $db_path/pfam.annotation.build36.gz $chr:$start-$stop - |";
        }
        elsif ($reference_build eq 'Build37') {
            $tabix_cmd .= " $db_path/pfam.annotation.build37.gz $chr:$start-$stop - |";
        }
        else { die "Please specify either 'Build36' or 'Build37' for the --reference-build parameter."; }

        #run tabix command
        my %domains;
        open(TABIX,$tabix_cmd) or die "Cannot open() the tabix command. Please check it is in your PATH. It can be installed from the samtools project. $!";
        while (my $tabline = <TABIX>) {
            chomp $tabline;
            my (undef,undef,undef,$csv_domains) = split /\t/,$tabline;
            my @domains = split /,/,$csv_domains;
            for my $domain (@domains) {
                $domains{$domain}++;
            }
        }
        close(TABIX);

        #print output
        my $all_domains = join(",",sort keys %domains);
        my $output_line = "$line\t";
        unless ($all_domains eq "") {
            $output_line .= "$all_domains\n";
        }
        else {
            $output_line .= "NA\n";
        }
        $out_fh->print($output_line);
    }

    return(1);
}

1;
