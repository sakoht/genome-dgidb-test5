
package Genome::Model::Tools::Capture::LimitToRoi;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# LimitToRoi - Converts a pileup file to a three column file of chromosome, position, and bases with q>20.
#					
#	AUTHOR:		Dan Koboldt (dkoboldt@watson.wustl.edu)
#
#	CREATED:	02/10/2010 by D.K.
#	MODIFIED:	02/10/2010 by D.K.
#
#	NOTES:	
#			
#####################################################################################################################################

use strict;
use warnings;
use FileHandle;
use Genome;                                 # using the namespace authorizes Class::Autouse to lazy-load modules under it

class Genome::Model::Tools::Capture::LimitToRoi {
	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		input_file	=> { is => 'Text', doc => "Input file of variants or positions", is_optional => 0, is_input => 1 },
		regions_file	=> { is => 'Text', doc => "Region coordinates in chrom-start-stop format", is_optional => 0, is_input => 1 },
		output_file     => { is => 'Text', doc => "Output file to receive limited variants", is_optional => 0, is_input => 1, is_output => 1 },
	],
};

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
    "Limits a set of variants to those within a set of ROIs"                 
}

sub help_synopsis {
    return <<EOS
This command limits a set of variants to those within a set of ROIs
EXAMPLE:	gmt capture limit-to-roi --input-file [my.variants] --regions-file [my.regions] --output-file [my.variants.roi]
EOS
}

sub help_detail {                           # this is what the user will see with the longer version of help. <---
    return <<EOS 

EOS
}


################################################################################################
# Execute - the main program logic
#
################################################################################################

sub execute {                               # replace with real execution logic.
	my $self = shift;

	## Get required parameters ##
	my $input_file = $self->input_file;
	my $regions_file = $self->regions_file;
	my $output_file = $self->output_file;
	
	## Call Varscan Limit ##

	if(-e $input_file && -e $regions_file)
	{
		my $cmd = "java -jar /gsc/scripts/lib/java/VarScan/VarScan.jar limit $input_file --regions-file $regions_file --output-file $output_file";
		system($cmd);
	}
	else
	{
		die "ERROR: Input file $input_file or regions file $regions_file not found!\n";
	}

	return 1;

}


1;

