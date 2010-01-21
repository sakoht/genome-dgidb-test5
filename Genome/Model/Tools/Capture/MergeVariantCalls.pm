
package Genome::Model::Tools::Capture::MergeVariantCalls;     # rename this when you give the module file a different name <--

#####################################################################################################################################
# MergeVariantCalls - Build Genome Models for Capture Datasets
#					
#	AUTHOR:		Dan Koboldt (dkoboldt@genome.wustl.edu)
#
#	CREATED:	12/09/2009 by D.K.
#	MODIFIED:	12/09/2009 by D.K.
#
#	NOTES:	
#			
#####################################################################################################################################

use strict;
use warnings;

use FileHandle;

use Genome;                                 # using the namespace authorizes Class::Autouse to lazy-load modules under it

## Declare global statistics hash ##

my %stats = ();

class Genome::Model::Tools::Capture::MergeVariantCalls {
	is => 'Command',                       
	
	has => [                                # specify the command's single-value properties (parameters) <--- 
		varscan_file	=> { is => 'Text', doc => "File of variants in VarScan format", is_optional => 0, is_input => 1 },
		glf_file	=> { is => 'Text', doc => "File of variants in glfSomatic format", is_optional => 0, is_input => 1 },
		output_file	=> { is => 'Text', doc => "Output file to contain merged results" , is_optional => 0, is_input => 1, is_output => 1},
		output_unique1	=> { is => 'Text', doc => "Output file for files unique to 1" , is_optional => 1, is_input => 1, is_output => 1},
		output_unique2	=> { is => 'Text', doc => "Output file for files unique to 2" , is_optional => 1, is_input => 1, is_output => 1},
		output_shared	=> { is => 'Text', doc => "Output file for shared" , is_optional => 1, is_input => 1, is_output => 1},
	],
	
	has_param => [
		lsf_resource => { default_value => 'select[model!=Opteron250 && type==LINUX64 && mem>6000] rusage[mem=6000]'},
       ],	
};

sub sub_command_sort_position { 12 }

sub help_brief {                            # keep this to just a few words <---
    "Merges VarScan and glfSomatic variant calls"                 
}

sub help_synopsis {
    return <<EOS
Merges VarScan and glfSomatic variant calls
EXAMPLE:	gt capture merge-variant-calls ...
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

	my $varscan_file = $self->varscan_file;
	my $glf_file = $self->glf_file;
	my $output_file = $self->output_file;
	
	if(!(-e $varscan_file && -e $glf_file))
	{
		die "One or more files didn't exist!\n";
	}

	## Run the merge using VarScan ##
	
	my $cmd = "java -Xms3000m -Xmx3000m -classpath ~dkoboldt/Software/VarScan net.sf.varscan.VarScan compare $varscan_file $glf_file merge $output_file";
	system($cmd);	
#	$cmd = "grep -v chrom $output_file >$output_file.temp";
#	system($cmd);
#	$cmd = "mv -f $output_file.temp $output_file";
#	system($cmd);

	$cmd = "java -Xms3000m -Xmx3000m -classpath ~dkoboldt/Software/VarScan net.sf.varscan.VarScan compare $varscan_file $glf_file intersect $output_file.shared";
	system($cmd);	

	$cmd = "java -Xms3000m -Xmx3000m -classpath ~dkoboldt/Software/VarScan net.sf.varscan.VarScan compare $varscan_file $glf_file unique1 $output_file.varscan-only";
	system($cmd);
	
	$cmd = "java -Xms3000m -Xmx3000m -classpath ~dkoboldt/Software/VarScan net.sf.varscan.VarScan compare $varscan_file $glf_file unique2 $output_file.sniper-only";
	system($cmd);		
	
	return 1;                               # exits 0 for true, exits 1 for false (retval/exit code mapping is overridable)
}






1;

