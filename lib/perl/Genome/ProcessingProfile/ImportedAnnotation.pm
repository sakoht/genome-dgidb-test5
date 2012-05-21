package Genome::ProcessingProfile::ImportedAnnotation;

use strict;
use warnings;

use Genome;

class Genome::ProcessingProfile::ImportedAnnotation{
    is => 'Genome::ProcessingProfile',
    has_param => [
        annotation_source => {
            is_optional => 0,
            doc => 'Where the annotation comes from (ensembl, genbank, etc.) This value is "combined-annotation" for a combined-annotation model',
        },
        interpro_version => {
            is_optional => 0,
            default_value => 4.5,
            doc => 'Version of interpro used to import interpro results', 
        },
        rna_seq_only => {
            default_value => 0,
            doc => 'True if only a minimal set of annotation files for RNA-Seq pipeline are needed',
        },
    ],
    
};

sub _resource_requirements_for_execute_build {
    my $self = shift;
    my $build = shift;

    return "-R 'rusage[mem=32000]' -M 32000000";
}

sub _execute_build{
    my $self = shift;
    my $build = shift;
    my $model = $build->model;


    my $source = $model->annotation_source;
    unless (defined $source){
        $self->error_message("Could not get imported annotation source!");
        return;
    }

    my $version = $build->version;
    unless (defined $version){
        $self->error_message("Could not get build version!");
        return;
    }

    my $data_directory = $build->data_directory;
    unless (defined $data_directory){
        $self->error_message("Could not get data directory for build!");
        return;
    }
    unless (-d $data_directory){
        Genome::Sys->create_directory($build->data_directory);
        unless (-d $data_directory) {
            $self->error_message("Failed to create new build dir: " . $build->data_directory);
            return;
        }
    }

    unless (-d $build->_annotation_data_directory) {
        Genome::Sys->create_directory($build->_annotation_data_directory);
        unless (-d $build->_annotation_data_directory) {
            $self->error_message("Failed to create annotation directory: ".$build->_annotation_data_directory);
        }
    }

    my $species_name = $build->species_name;
    unless (defined $species_name){
        $self->error_message('Could not get species name!');
        return;
    }

    unless ($self->rna_seq_only) {
        my $name = ucfirst(lc($source));
        my $importer_class_name = join('::', 'Genome', 'Db', $name, 'Import', 'Run');
        my $cmd = $importer_class_name->execute(
            data_set => 'Core', 
            imported_annotation_build => $build,
        );

        my $tiering_cmd;
        my $annotation_directory = $build->_annotation_data_directory;
        my $bitmasks_directory = $annotation_directory."/tiering_bitmasks";
        unless ( -d $bitmasks_directory) {
            Genome::Sys->create_directory($bitmasks_directory);
            unless (-d $bitmasks_directory) {
                $self->error_message("Failed to create new build dir: " . $bitmasks_directory);
                return;
            }
        }
        my $bed_directory = $annotation_directory."/tiering_bed_files_v3";
        unless ( -d $bed_directory) {
            Genome::Sys->create_directory($bed_directory);
            unless (-d $bed_directory) {
                $self->error_message("Failed to create new build dir: " . $bed_directory);
                return;
            }
        }
        if ($species_name eq 'human') {
            $tiering_cmd = Genome::Model::Tools::FastTier::MakeTierBitmasks->create(
                output_directory => $annotation_directory."/tiering_bitmasks",
                reference_sequence => $build->reference_sequence->fasta_file,
                transcript_version => $build->version,
                annotation_model => $build->model->id,
                ucsc_directory => $build->reference_sequence->get_or_create_ucsc_tiering_directory,
            );
        }
        elsif ($species_name eq 'mouse') {
            $tiering_cmd = Genome::Model::Tools::FastTier::MakeMouseBitmasks->create(
                output_directory => $annotation_directory."/tiering_bitmasks",
                reference_sequence => $build->reference_sequence->fasta_file,
            );
        }

        if ($species_name eq 'human' or $species_name eq 'mouse') {
            $tiering_cmd->execute;
            foreach my $file ($tiering_cmd->tier1_output, $tiering_cmd->tier2_output, $tiering_cmd->tier3_output, $tiering_cmd->tier4_output) {
                my $bed_name = $file;
                $bed_name =~ s/tiering_bitmasks/tiering_bed_files_v3/;
                $bed_name =~ s/bitmask/bed/;
                my $convert_cmd = Genome::Model::Tools::FastTier::BitmaskToBed->create(
                    output_file => $bed_name,
                    bitmask => $file,
                );
                $convert_cmd->execute;
            }
        }

        my $ucsc_directory = $annotation_directory."/ucsc_conservation";
        Genome::Sys->create_symlink($build->reference_sequence->get_or_create_ucsc_conservation_directory, $ucsc_directory); 

        #generate the rna seq files
        $self->generate_rna_seq_files($build);

        #Make ROI FeatureList
        $build->get_or_create_roi_bed;

    }

    return 1;
}

sub get_ensembl_info {
    my $self = shift;
    my $version = shift;
    my ($eversion,$ncbiversion) = split(/_/,$version);

    my $host = defined $ENV{GENOME_DB_ENSEMBL_HOST} ? $ENV{GENOME_DB_ENSEMBL_HOST} : 'mysql1';
    my $user = defined $ENV{GENOME_DB_ENSEMBL_USER} ? $ENV{GENOME_DB_ENSEMBL_USER} : 'mse'; 
    my $password = defined $ENV{GENOME_DB_ENSEMBL_PASSWORD} ? $ENV{GENOME_DB_ENSEMBL_PASSWORD} : undef;

    return ($host, $user, $password);
}

sub generate_rna_seq_files {
    my $self = shift;
    my $build = shift;

    my $cmd = Genome::Model::ImportedAnnotation::Command::CopyRibosomalGeneNames->create(output_file => join('/', $build->_annotation_data_directory, 'RibosomalGeneNames.txt'), species_name => $build->species_name);
    unless($cmd->execute){
        $self->error_message("Failed to generate the ribosomal gene name file!");
        return;
    }

    unless($build->generate_RNA_annotation_files('gtf', $build->reference_sequence_id)){
        $self->error_message("Failed to generate RNA Seq files!");
        return;
    }

    return 1;
}

sub calculate_snapshot_date {
    my ($self, $genbank_file) = @_;
    my $output = `ls -l $genbank_file`;
    my @parts = split(" ", $output);
    my $date = $parts[5];
    return $date;
}

1;
