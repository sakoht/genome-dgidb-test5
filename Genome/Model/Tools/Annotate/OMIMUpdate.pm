package Genome::Model::Tools::Annotate::OMIMUpdate;

########################################################################################################################
# OMIMUpdate.pm - A module for updating the local OMIM amino acid database to reflect the current OMIM database.
#					
#	AUTHOR:		Will Schierding (wschierd@genome.wustl.edu)
#
#	CREATED:	3/09/2010 by W.S.
#	MODIFIED:	3/09/2010 by W.S.
#
#	NOTES:	
#			
#####################################################################################################################################

   use warnings;
   use strict;
   use Bio::Phenotype::OMIM::OMIMparser;
   use Bio::Phenotype::OMIM::OMIMentry;
   use Bio::Phenotype::OMIM::OMIMentryAllelicVariant;
   use Net::FTP;
   use Cwd;
   use Getopt::Long;

class Genome::Model::Tools::Annotate::OMIMUpdate {

	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		omim_folder	=> { is => 'Text', doc => "Path to the current local OMIM files", is_optional => 1 },
		omim_url	=> { is => 'Text', doc => "URL to the online OMIM repository", is_optional => 1 },
		output_file	=> { is => 'Text', doc => "Output file name for flatfile of amino acid changes" , is_optional => 1},
	],
};

sub help_brief {                            # keep this to just a few words <---
    "Update Local OMIM database"
}

sub help_synopsis {
    return <<EOS
A module for updating the downloaded OMIM database to reflect the current OMIM database.
EXAMPLE:	gmt annotate OMIM-update ...
EOS
}

sub help_detail {                           # this is what the user will see with the longer version of help. <---
    return <<EOS 
A module for updating the downloaded OMIM database to reflect the current OMIM database.
EOS
}


################################################################################################
# Execute - the main program logic
#
################################################################################################

sub execute {                               # replace with real execution logic.

my $self = shift;
my $URL = $self->omim_url;
my $OMIMpath = $self->omim_folder;
my $OMIM_DB = $self->output_file;

my ($OMIMINPUT, $OMIMZINPUT, $OMIMfile);

print "retrieving file from OMIM\n";
#zipped file
$OMIMZINPUT = 'omim.txt.Z';
#file from unzipping
$OMIMINPUT = 'omim.txt';
$OMIMpath ||= '/gscmnt/200/medseq/analysis/software/resources/OMIM/OMIM_Will/';
chdir ($OMIMpath);
my $dir = getcwd;
print "Working Directory: $dir";
$OMIMfile ||= "$OMIMpath/$OMIMINPUT";

system ( rm, $OMIMZINPUT);
system ( rm, $OMIMINPUT);

#directory on OMIM server
$URL ||= 'ftp://ftp.ncbi.nih.gov/repository/OMIM/'.$OMIMZINPUT;
system ( wget, $URL);

print "unzipping OMIM file\n";
system ( gunzip, $OMIMZINPUT);

print "Writing OMIM_aa File...\n";
my $omim_parser = Bio::Phenotype::OMIM::OMIMparser->new(-omimtext => $OMIMfile );

# amino acid output file
$OMIM_DB ||= 'OMIM_aa_will.csv';
unless (open(OMIM_DB,">$OMIM_DB")) {
    die "Could not open output file '$OMIM_DB' for writing";
}
#output the additional info incase it's important -- so far, nothing there looks needed for our purposes
my $OMIM_DB_ADDITIONAL = $OMIM_DB.'ADDITIONAL_OMIM.csv';
unless (open(OMIM_DB_ADDITIONAL,">$OMIM_DB_ADDITIONAL")) {
    die "Could not open output file '$OMIM_DB_ADDITIONAL' for writing";
}

# start amino acid file output
print OMIM_DB "gene\tomimentry\tposition\taa_ori\taa_mut\tdescription\n"; 

# to split OMIM file, call OMIMparser, OMIMentry, and OMIMentryAllelicVariant
# Function: Returns an Bio::Phenotype::OMIM::OMIMentry or undef once the end of the omim text file is reached.
while ( my $omim_entry = $omim_parser->next_phenotype() ) {
	for my $variant ($omim_entry->each_AllelicVariant()) {
		my $mim = $omim_entry->MIM_number;
		my $number = $variant->number;
		my $symbol = $variant->symbol;
		my $aa_ori = $variant->aa_ori;
		my $aa_mut = $variant->aa_mut;
		my $pos = $variant->position;
		my $add_mut = $variant->additional_mutations;
		my $mimnum = "$mim$number";

		#Alanine 	Ala 	A
		#Arginine 	Arg 	R
		#Asparagine 	Asn 	N
		#Aspartic acid 	Asp 	D
		#Cysteine 	Cys 	C
		#Glutamic acid 	Glu 	E
		#Glutamine 	Gln 	Q
		#Glycine 	Gly 	G
		#Histidine 	His 	H
		#Isoleucine 	Ile 	I
		#Leucine 	Leu 	L
		#Lysine 	Lys 	K
		#Methionine 	Met 	M
		#Phenylalanine 	Phe 	F
		#Proline 	Pro 	P
		#Serine 	Ser 	S
		#Threonine 	Thr 	T
		#Tryptophan 	Trp 	W
		#Tyrosine 	Tyr 	Y
		#Valine 	Val 	V
		#special cases:
			#asparagine/aspartic acid - asx - B
			#glutamine/glutamic acid - glx - Z 

# WHAT TO DO HERE:
#HBB	141900.04	24	GGT	GGA
#ALB, 1-BP INS	103600	267	AAT	AAA
#GHR	600946	180	GAA	GAG
#SCN4A	603967	1456	G	LGU

#PAH	261600	399	?	?

#SPTA1, 3-BP INS	182860	154	L	DUP

		#convert OMIM amino acids to common format used in house

		$aa_ori =~ s/ALA/A/;
		$aa_ori =~ s/ARG/R/;
		$aa_ori =~ s/ASN/N/;
		$aa_ori =~ s/ASP/D/;
		$aa_ori =~ s/CYS/C/;
		$aa_ori =~ s/GLU/E/;
		$aa_ori =~ s/GLN/Q/;
		$aa_ori =~ s/GLY/G/;
		$aa_ori =~ s/HIS/H/;
		$aa_ori =~ s/ILE/I/;
		$aa_ori =~ s/LEU/L/;
		$aa_ori =~ s/LYS/K/;
		$aa_ori =~ s/MET/M/;
		$aa_ori =~ s/PHE/F/;
		$aa_ori =~ s/PRO/P/;
		$aa_ori =~ s/SER/S/;
		$aa_ori =~ s/THR/T/;
		$aa_ori =~ s/TRP/W/;
		$aa_ori =~ s/TYR/Y/;
		$aa_ori =~ s/VAL/V/;
		$aa_ori =~ s/ASX/B/;
		$aa_ori =~ s/GLX/Z/;
		$aa_ori =~ s/TER/*/;
		$aa_ori =~ s/SEC/U/;
		$aa_ori =~ s/INS/-/;
		$aa_ori =~ s/DUP/-/;
		$aa_ori =~ s/DEL/-/;
		$aa_ori =~ s/GGT/?/;
		$aa_ori =~ s/GGA/?/;
		$aa_ori =~ s/GAA/?/;
		$aa_ori =~ s/GAG/?/;
		$aa_ori =~ s/AAT/?/;
		$aa_ori =~ s/AAA/?/;
		$aa_ori =~ s/LGU/?/;
		$aa_ori =~ s/IVS/-/;


		$aa_mut =~ s/ALA/A/;
		$aa_mut =~ s/ARG/R/;
		$aa_mut =~ s/ASN/N/;
		$aa_mut =~ s/ASP/D/;
		$aa_mut =~ s/CYS/C/;
		$aa_mut =~ s/GLU/E/;
		$aa_mut =~ s/GLN/Q/;
		$aa_mut =~ s/GLY/G/;
		$aa_mut =~ s/HIS/H/;
		$aa_mut =~ s/ILE/I/;
		$aa_mut =~ s/LEU/L/;
		$aa_mut =~ s/LYS/K/;
		$aa_mut =~ s/MET/M/;
		$aa_mut =~ s/PHE/F/;
		$aa_mut =~ s/PRO/P/;
		$aa_mut =~ s/SER/S/;
		$aa_mut =~ s/THR/T/;
		$aa_mut =~ s/TRP/W/;
		$aa_mut =~ s/TYR/Y/;
		$aa_mut =~ s/VAL/V/;
		$aa_mut =~ s/ASX/B/;
		$aa_mut =~ s/GLX/Z/;
		$aa_mut =~ s/TER/*/;
		$aa_mut =~ s/SEC/U/;
		$aa_mut =~ s/INS/-/;
		$aa_mut =~ s/DUP/-/;
		$aa_mut =~ s/DEL/-/;
		$aa_mut =~ s/GGT/?/;
		$aa_mut =~ s/GGA/?/;
		$aa_mut =~ s/GAA/?/;
		$aa_mut =~ s/GAG/?/;
		$aa_mut =~ s/AAT/?/;
		$aa_mut =~ s/AAA/?/;
		$aa_mut =~ s/LGU/?/;
		$aa_mut =~ s/IVS/-/;

		#split gene name into gene name and optional notes
		my ($symbol1, $symbol2) = split(",",$symbol);

		#check if gene name is defined
		if ($symbol ne ''){
			#and if amino acid info is defined
			if ($aa_ori ne ''){
				my $avs = join("\t", $symbol1,$mimnum,$pos,$aa_ori,$aa_mut,$add_mut);
				print OMIM_DB "$avs\n"; 
			}
			if ($aa_ori eq ''){
				my $avs = join("\t", $symbol1,$mimnum,$pos,$aa_ori,$aa_mut,$add_mut);
				print OMIM_DB_ADDITIONAL "$avs\n"; 
			}
		}
	}
}   

close(OMIM_DB);
close(OMIM_DB_ADDITIONAL);
print "Finished Writing OMIM_aa File\n";

	return 1;                               # exits 0 for true, exits 1 for false (retval/exit code mapping is overridable)
}



