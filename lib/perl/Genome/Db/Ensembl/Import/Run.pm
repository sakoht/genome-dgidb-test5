package Genome::Db::Ensembl::Import::Run;

use strict;
use warnings;
use Genome;

class Genome::Db::Ensembl::Import::Run {
    is => 'Command::V2',
    doc => 'Import a version of ensembl annotation',
    has => [
        data_set => {
            is => 'Text',
            doc => 'Ensembl data set to import (ex )',
            is_optional => 1, #TODO: do we even need this param?
        },
        imported_annotation_build => {
            is => 'Genome::Model::Build::ImportedAnnotation',
            doc => 'Imported anntation build',
        },
    ],
};

sub help_brief {
}

sub help_detail {
    return <<EOS
EOS
}

sub execute {
    my $self = shift;
    my $data_set = $self->data_set;
    my $build = $self->imported_annotation_build;
    my $data_directory = $build->data_directory;
    my $version= $build->version;
    my $species_name = $build->species_name;
    
    #download the Ensembl API to $build->data_directory
    my $api_version = $self->ensembl_version_string($version);
    my $api_cmd = Genome::Db::Ensembl::Import::InstallEnsemblApi->execute(
        version => $api_version,
        output_directory => $data_directory,
    );
    
    my $annotation_data_directory = join('/', $data_directory, 'annotation_data');
    unless(-d $annotation_data_directory){
        Genome::Sys->create_directory($annotation_data_directory);
        unless (-d $annotation_data_directory) {
            $self->error_message("Failed to create new annotation data dir: " . $annotation_data_directory);
            return;
        }
    }

    my $log_file = $data_directory . "/" . 'ensembl_import.log';
    my $dump_file = $data_directory . "/" . 'ensembl_import.dump';
    
    my ($host, $user, $pass) = $self->get_ensembl_info($version);
    
    my $command = join(" " , 
        "genome db ensembl import create-annotation-structures", 
        "--data-directory $annotation_data_directory",
        "--version $version",
        "--host $host",
        "--user $user",
        ($pass ? "--pass $pass" : ''),
        "--species $species_name",
        "--log-file $log_file",
        "--dump-file $dump_file");
    $build->prepend_api_path_and_execute(cmd => $command);

#TODO: run tony's fix it scripts
#TODO: Does import interpro go here or in processing_profile _execute_body
#TODO: does ROI featurelist generation go here or in processing_profile
#TODO: does rna_seq file gen or tiering file gen go here or in processing profile
}

#TODO: make this do something reasonable, like use the environment variables
# if they exist or otherwise connect to the public ensembl server YAY
sub get_ensembl_info {
    my $self = shift;
    my $version = shift;
    my ($eversion,$ncbiversion) = split(/_/,$version);
    # my $path = "/gsc/scripts/share/ensembl-".$eversion;

    # unless(-d $path) {
        # die "$path  does not exist, is $eversion for ensembl installed?";
    # }

    return ("mysql1","mse",undef); # no pass word needed here. all else const
}

sub ensembl_version_string {
    my $self = shift;
    my $ensembl = shift;

    # <ens version>_<ncbi build vers><letter>
    # 52_36n

    my ( $e_version_number, $ncbi_build ) = split( /_/x, $ensembl );
    return $e_version_number;
}

1;
