package Genome::Model::Tools::Allpaths::DeNovoAssemble;

use strict;
use warnings;

use Genome;
use File::Path qw(make_path);

my $PICARD_TOOLS_DIR="/gsc/scripts/lib/java/samtools/picard-tools-1.52";

class Genome::Model::Tools::Allpaths::DeNovoAssemble {
    is => 'Genome::Model::Tools::Allpaths::Base',
    has => [
        pre => {
            is => 'Text',
            doc => 'The output directory prefix.' 
        },
        ploidy => {
            is => 'Text',
            doc => 'Ploidy',
        },
        in_group_file => {
            is => 'Text',
            doc => 'in_group_file',
        },
        in_libs_file => {
            is => 'Text',
            doc => 'in_libs_file',
        },
        run => {
            is => 'Text',
            doc => 'name of the run',
            default_value => 'run',
        },
        sub_dir => {
            is => 'Text',
            doc => 'name of subdirectory',
            default_value => 'test',
        },
        overwrite => {
            is => 'Boolean',
            doc => 'should existing results be overwritten',
            default_value => 1,
        },
        reference_name => {
            is => 'String',
            doc => 'name of the reference',
            default_value => 'sample',
        },
    ],
};

sub help_brief {
    'run ALLPATHS de novo assembler';
}

sub help_detail {
    return;
}

sub execute {
    my $self = shift;

    if (not $self->pre or not -d $self->pre) {
        $self->error_message("Output directory prefix does not exist");
        return;
    }

    my $output_dir = $self->pre."/".$self->reference_name;
    if (! -d $output_dir ) {
        make_path($output_dir);
    }

    # Prepare
    # -need group file (generate based on inputs)
    # -need library file (generate based on inputs)
    # -separate inputs by library
    # -must be at least 2 paired libs, one short, one long
    # -may have add'l long frag lib
    # -may have add'l long jumping paired lib

    if (! -d $output_dir."/data") {
        make_path($output_dir."/data");
    }

    my $prepare_cmd = 'ulimit -s 100000 && PATH='.$self->allpaths_version_directory($self->version).':'.$ENV{PATH}.' PrepareAllPathsInputs.pl PICARD_TOOLS_DIR='.$PICARD_TOOLS_DIR.' DATA_DIR='.$output_dir.'/data PLOIDY='.$self->ploidy.' IN_GROUPS_CSV='.$self->in_group_file.' IN_LIBS_CSV='.$self->in_libs_file;

    $self->status_message("Run PrepareAllPathsInput");
    Genome::Sys->shellcmd(cmd => $prepare_cmd); 
    if ($? != 0) {
        $self->error_message("Failed to run PrepareAllPathsInput: $@");
        return;
    }

    my $overwrite;
    if ($self->overwrite) {
        $overwrite="True";
    }
    else {
        $overwrite = "False";
    }
    my $cmd = 'ulimit -s 100000 && PATH='.$self->allpaths_version_directory($self->version).':'.$ENV{PATH}.' RunAllPathsLG PRE='.$self->pre.' REFERENCE_NAME='.$self->reference_name.' DATA_SUBDIR=data RUN='.$self->run.' SUBDIR='.$self->sub_dir.' TARGETS=standard OVERWRITE='.$overwrite;

    $self->status_message("Run ALLPATHS de novo");
    Genome::Sys->shellcmd(cmd => $cmd);
    if ( $? != 0) {
        $self->error_message("Failed to run ALLPATHS de novo: $@");
        return;
    }
    $self->status_message("Run ALLPATHS de novo...OK");

    return 1;
}

1;

