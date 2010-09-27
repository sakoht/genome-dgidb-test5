package Genome::Model::Tools::Assembly::CreateOutputFiles::Newbler;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Assembly::CreateOutputFiles::Newbler {
    is => 'Genome::Model::Tools::Assembly::CreateOutputFiles',
    has => [
        acefile => {
            is => 'Text',
            doc => 'Ace file to get fasta and qual from',
            #is_optional => 1,
        },
        assembly_directory => {
            is => 'Text',
            doc => 'Main Assembly directory, not assembly edit_dir',
        },
        run_core_gene_survey => {
            is => 'Boolean',
            doc => 'Runs core gene survey',
            is_optional => 1,
        },
	core_gene_option => {
            is => 'Text',
            doc => 'Core gene survey option: either bact or archaea',
            valid_values => ['bact', 'archaea'],
            is_optional => 1,
	},
    ],
    has_optional_transient => [
	_contigs_bases_file      => { is => 'Text', doc => 'Assembly contigs.bases file'},
	_contigs_quals_file      => { is => 'Text', doc => 'Assembly contigs.quals file'},
	_gap_file                => { is => 'Text', doc => 'Assembly gap.txt file'},
	_reads_placed_file       => { is => 'Text', doc => 'Assembly reads.placed file'},
	_read_info_file          => { is => 'Text', doc => 'Assembly readinfo.txt file'},
	_supercontigs_agp_file   => { is => 'Text', doc => 'Assembly supercontigs.agp file'},
	_supercontigs_fasta_file => { is => 'Text', doc => 'Assembly supercontigs.fasta file'},
	_stats_file              => { is => 'Text', doc => 'Assembly stats.txt file'},
    ],
};

sub help_brief {
    'Tool to create assembly output files for newbler assemblies';
}

sub help_synopsis {
    return <<EOS
gmt assembly create-output-file newbler --acefile /gscmnt/111/newbler_assembly/contigs.ace --assembly-directory /gscmnt/111/newbler_assembly	
EOS
}

sub help_detail {
    return <<EOS

EOS
}

sub execute {
    my $self = shift;

    #must run from 64 bit machine
    my $archos = `uname -a`;
    unless ($archos =~ /64/) {
	$self->error_message("Create output files for newbler must run from 64 bit machines");
	return;
    }

    #resolve acefile location
    my $acefile = $self->acefile;
    unless (-s $acefile) {
	$acefile = $self->assembly_directory."/edit_dir/$acefile";
	unless (-s $acefile) {
	    $self->error_message("Can't find ace file, neither $acefile nor ".$self->assembly_directory."/edit_dir/$acefile exists");
	    return;
	}
    }

    #set in/out put file names values
    unless ($self->_set_transients()) {
	$self->error_message("Failed to define and set assembly files");
	return;
    }

    #create input fasta and qual files from sff files
    $self->status_message("Creating input fasta and qual files from sff files");
    my $inputs = Genome::Model::Tools::Assembly::CreateOutputFiles::InputFromSff->create (
	directory => $self->assembly_directory,
	);
    unless ($inputs->execute) {
	$self->error_message("Failed to create input files from sff files");
	return;
    }

    #create sorted contigs.bases and contigs.qual files
    $self->status_message("Creating contigs.bases and contigs.quals files");
    my $contigs = Genome::Model::Tools::Assembly::CreateOutputFiles::ContigsFromAce->create (
	acefile => $acefile,
	fasta_out => $self->_contigs_bases_file,
	qual_out => $self->_contigs_quals_file,
	directory => $self->assembly_directory,
	);
    unless ($contigs->execute) {
	$self->error_message("Failed to create contigs bases and qual files from acefile");
	return;
    }
    sleep(1);

    #create msi.readinfo.txt file
    $self->status_message("Creating readinfo.txt file");
    my $readinfo = Genome::Model::Tools::Assembly::CreateOutputFiles::ReadInfo->create (
	acefile => $acefile,
	output_file => $self->_read_info_file,
	directory => $self->assembly_directory,
	);
    unless ($readinfo->execute) {
	$self->error_message("Failed to create msi.readinfo.txt file");
	return;
    }

    #create msi.reads.placed file
    $self->status_message("Creating reads.placed file");
    my $reads_placed = Genome::Model::Tools::Assembly::CreateOutputFiles::ReadsPlaced->create (
	read_info_file => $self->_read_info_file,
	gap_file => $self->_gap_file,
	contigs_bases_file => $self->_contigs_bases_file,
	output_file => $self->_reads_placed_file,
	directory => $self->assembly_directory,
	);
    unless ($reads_placed->execute) {
	$self->error_message("Failed to create reads.placed file");
	return;
    }
    sleep(1);

    #create reads.unplaced files (reads.unplaced and reads.unplaced.fasta)
    $self->status_message("Creating reads.unplaced and reads.unplaced.fasta files");
    my $unplaced = Genome::Model::Tools::Assembly::CreateOutputFiles::ReadsUnplaced->create(
	reads_placed_file => $self->_reads_placed_file,
	directory => $self->assembly_directory,
	);
    unless ($unplaced) {
	$self->error_message("Failed to create reads-unplaced");
	return;
    }
    unless ($unplaced->execute) {
	$self->error_message("Failed to execute reads-unplaced");
	return;
    }
    sleep(1);

    #create supercontigs.agp file
    $self->status_message("Creating supercontigs.agp file");
    my $agp = Genome::Model::Tools::Assembly::CreateOutputFiles::SupercontigsAgp->create (
	contigs_bases_file => $self->_contigs_bases_file,
	gap_file => $self->_gap_file,
	output_file => $self->_supercontigs_agp_file,
	directory => $self->assembly_directory,
	);
    unless ($agp->execute) {
	$self->error_message("Failed to create supercontigs.agp file");
	return;
    }

    #create supercontigs.fasta
    $self->status_message("Creating supercontigs.fasta file");
    my $s_fa = Genome::Model::Tools::Assembly::CreateOutputFiles::SupercontigsFasta->create (
	contigs_bases_file => $self->_contigs_bases_file,
	gap_file => $self->_gap_file,
	output_file => $self->_supercontigs_fasta_file,
	directory => $self->assembly_directory,
	);
    unless ($s_fa->execute) {
	$self->error_message("Failed to create msi.supercontigs.fasta file");
	return;
    }
    #run core gene survey .. does system call to deployed script
    if ($self->run_core_gene_survey) {
        $self->status_message("Running core gene survey");
        my $gene_option = ($self->core_gene_option) ? $self->core_gene_option : 'bact';
        my $survey = Genome::Model::Tools::Assembly::CreateOutputFiles::CoreGeneSurvey->create (
            core_gene_option => $gene_option,
            subject_file => $self->_contigs_bases_file,
            );
        unless ($survey->execute) {
            $self->error_message("Failed to execute core gene survey");
            return;
        }
    }

    #create stats.txt file
    $self->status_message("Creating stats.txt file");
    my $stats = Genome::Model::Tools::Assembly::Stats::Newbler->create (
	#acefile => $self->acefile,
	assembly_directory => $self->assembly_directory,
	out_file => $self->_stats_file,
	);
    unless ($stats->execute) {
	$self->error_message("Failed to create stats.txt file");
	return;
    }
    return 1;
}

sub _set_transients {
    my $self = shift;
    
    my $edit_dir = $self->assembly_directory.'/edit_dir';

    $self->_contigs_bases_file("$edit_dir/contigs.bases");
    $self->_contigs_quals_file("$edit_dir/contigs.quals");
    $self->_gap_file("$edit_dir/gap.txt");
    $self->_reads_placed_file("$edit_dir/reads.placed");
    $self->_read_info_file("$edit_dir/readinfo.txt");
    $self->_supercontigs_agp_file("$edit_dir/supercontigs.agp");
    $self->_supercontigs_fasta_file("$edit_dir/supercontigs.fasta");
    $self->_stats_file("$edit_dir/stats.txt");
    
    return 1;
}

1;
