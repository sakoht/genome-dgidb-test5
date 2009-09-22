package Genome::Model::Command::Build::ViromeScreen::Screen;

use strict;
use warnings;

use Genome;
use IO::File;
use Data::Dumper;

class Genome::Model::Command::Build::ViromeScreen::Screen {
    is => 'Genome::Model::Event',
};

sub execute {
    my $self = shift;

    unless (-d $self->build->data_directory) {
	$self->error_message("Run directory does not exist");
	return;
    }

    my $fasta_name = $self->model->subject_name.'.fna';
    my $screen_dir = $self->build->data_directory.'/virome_screen';

    unless (-s $screen_dir.'/'.$fasta_name) {
	$self->error_message("Error: Can not find file: fasta_file");
	return;
    }

    print $self->build->log_file."LogFile\n";

    my $run = Genome::Model::Tools::ViromeScreening->create (
	fasta_file   => $screen_dir.'/'.$fasta_name,
	barcode_file => $self->build->barcode_file,
	dir          => $self->build->data_directory,
	logfile      => $screen_dir.'/'.$self->build->log_file, #THIS IS NOT AN INPUT FILE??
    );

    unless ($run) {
	$self->error_message("Failed to create virome screen run");
	return;
    }

    print Dumper $run;
    return 1;

    unless ($run->execute) {
	$self->error_message("Failed virome screen run");
	return 1;
    }

    return 1;
}

1;
