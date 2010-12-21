package Genome::Model::GenePrediction::Eukaryotic::RepeatMasker;

# There seems to be a Genome::Model::Tools::RepeatMasker command tree that
# could replace this module, with some minor modifications.

use strict;
use warnings;

use Genome;
use File::Temp 'tempdir';
use Carp 'confess';
use Bio::SeqIO;
use File::chdir;
use File::Path 'rmtree';

# TODO: Probably shouldn't be using this patched version of bioperl
require '/gsc/scripts/opt/bacterial-bioperl/Bio/Tools/Run/RepeatMasker.pm';

class Genome::Model::GenePrediction::Eukaryotic::RepeatMasker {
    is => 'Command',
    has => [
        fasta_file => { 
            is  => 'Path',
            is_input => 1,
            doc => 'Fasta file to be masked',
        },
    ],
    has_optional => [
        masked_fasta => { 
            is => 'Path',
            is_input => 1,
            is_output => 1,
            doc => 'Masked sequence is placed in this file (fasta format)' 
        },
        repeat_library => {
            is => 'Path',
            is_input => 1,
            doc => 'Repeat library to pass to RepeatMasker', 
        },
	    species	=> {
            is  => 'Text',
            is_input => 1,
            doc => 'Species name',
		},
	    xsmall	=> {
            is  => 'Boolean',
            is_input => 1,
            default => 0,
            doc => 'If set, masked sequence is marked by lowercasing bases instead of using N',
		},
        temp_working_directory => {
            is => 'Path',
            is_input => 1,
            doc => 'Temporary working files are written here',
        },
        skip_masking => {
            is => 'Boolean',
            is_input => 1,
            default => 0,
            doc => 'If set, masking is skipped',
        },
    ], 
};

sub help_brief {
    return "RepeatMask the contents of the input file and write the result to the output file";
}

sub help_synopsis {
    return <<"EOS"
EOS
}

sub help_detail {
    return <<"EOS"
Need documenation here.
EOS
}

sub execute {
    my $self = shift;

    unless (-e $self->fasta_file and -s $self->fasta_file) {
        confess "File does not exist or has no size at " . $self->fasta_file;
    }

    unless (defined $self->repeat_library or defined $self->species) {
        confess "Either repeat library or species must be defined!";
    }
    elsif (defined $self->repeat_library and defined $self->species) {
        $self->warning_message("Both repeat library and species are specified, choosing repeat library!");
    }

    if ($self->fasta_file =~ /\.bz2$/) {
        my $unzipped_file = Genome::Utility::FileSystem->bunzip($self->fasta_file);
        confess "Could not unzip fasta file at " . $self->fasta_file unless defined $unzipped_file;
        $self->fasta_file($unzipped_file);
    }
    
    # If masked fasta path not given, then put it in the same location as the input fasta file... Using
    # File::Spec's rel2abs function to convert fasta path to an absolute location if needed.
    if (not defined $self->masked_fasta) {
        my $fasta_path = File::Spec->rel2abs($self->fasta_file);
        my $default_masked_location =  "$fasta_path.repeat_masker";
        $self->status_message("Masked fasta file path not given, defaulting to $default_masked_location");
        $self->masked_fasta($default_masked_location);
    }

    if (-e $self->masked_fasta) {
        $self->warning_message("Removing existing file at " . $self->masked_fasta);
        unlink $self->masked_fasta;
    }

    if ($self->skip_masking) {
        $self->status_message("skip_masking flag is set, copying input fasta to masked fasta location");
        my $rv = Genome::Utility::FileSystem->copy_file($self->fasta_file, $self->masked_fasta);
        confess "Trouble executing copy of " . $self->fasta_file . " to " . $self->masked_fasta unless defined $rv and $rv;
        $self->status_message("Copy of input fasta at " . $self->fasta_file . " to masked fasta path at " .
            $self->masked_fasta . " successful, exiting!");
        return 1;
    }

    if (not defined $self->temp_working_directory) {
        my $temp_dir = tempdir(
            'RepeatMasker-XXXXXX',
            DIR => '/tmp/',
            CLEANUP => 0,
            UNLINK => 0,
        );
        chmod(0775, $temp_dir);
        $self->temp_working_directory($temp_dir);
        $self->status_message("Not given temp working directory, using $temp_dir");
    }

    my $input_fasta = Bio::SeqIO->new(
        -file => $self->fasta_file,
        -format => 'Fasta',
    );

    my $masked_fasta = Bio::SeqIO->new(
        -file => '>' . $self->masked_fasta,
        -format => 'Fasta',
    );

    # FIXME I (bdericks) had to patch this bioperl module to not fail if there is no repetitive sequence
    # in a sequence we pass in. This patch either needs to be submitted to BioPerl or a new wrapper for 
    # RepeatMasker be made for in house. I don't like relying on patched version of bioperl that isn't
    # tracked in any repo...
    my $masker;
    if (defined $self->repeat_library) {
    	$masker = Bio::Tools::Run::RepeatMasker->new(
            lib => $self->repeat_library, 
            xsmall => $self->xsmall, 
            verbose => 0,
            dir => $self->temp_working_directory,
        );
    }
    elsif (defined $self->species) {
    	$masker = Bio::Tools::Run::RepeatMasker->new(
            species => $self->species, 
            xsmall => $self->xsmall, 
            verbose => 0,
            dir => $self->temp_working_directory,
        );
    } 

    # FIXME This is the only way I know of to force this bioperl object to use the temp directory I want. If
    # this is not specified, the tool fails when it can't open an output file in the temp directory (because
    # the default temp directory doesn't have the permissions set appropriately...). If some bioperl guru
    # knows how to specify this during object creation and not have to violate class privacy like I am here,
    # please do.
    $masker->{_tmpdir} = $self->temp_working_directory;

    # FIXME RepeatMasker emits a warning when no repetitive sequence is found. I'd prefer to not have
    # this displayed, as this situation is expected and the warning message just clutters the logs.
    while (my $seq = $input_fasta->next_seq()) {
        local $CWD = $self->temp_working_directory; # More shenanigans to get repeat masker to not put temp dir in cwd,
                                                    # which could be a snapshot and cause problems
        $masker->run($seq);
        my $masked_seq = $masker->masked_seq();
        $masked_seq = $seq unless defined $masked_seq; # If no masked sequence found, write original seq to file
        $masked_fasta->write_seq($masked_seq);

        # Repeat masker makes an ungodly number of files in the working directory, especially if checking a large
        # number of sequences. To prevent this from getting unwieldy, remove these files after each sequence
        # TODO Use glob or something here instead of a system command
        my $rv = system("rm -rf " . $self->temp_working_directory . "/*");
        unless (defined $rv and $rv == 0) {
            $self->error_message("Could not remove files from repeat masker working directory " . $self->temp_working_directory)
        }
    }   

    # TODO Use LSF temp directory so there's automatic cleanup... for now, do it manually
    my $rv = rmtree($self->temp_working_directory);
    $self->error_message("Could not remove working directory at " . $self->temp_working_directory) unless defined $rv and $rv;
    return 1;
}

1;
