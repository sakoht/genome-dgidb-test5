#!/gsc/bin/perl

# This test confirms the ability to create a processing profile and then create
# a genome model using that processing profile

use strict;
use warnings;

use Data::Dumper;
use above "Genome";
use Command;
use Test::More tests => 102;
use Test::Differences;
use File::Path;


$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

# Attributes for new model and processing profile

my $indel_finder = 'maq0_6_3';
my $model_name = "test_$ENV{USER}";
my $subject_name = 'H_GV-933124G-skin1-9017g';
my $dna_type = 'genomic dna';
my $align_dist_threshold = '0';
my $reference_sequence = 'refseq-for-test';
my $genotyper = 'maq0_6_3';
my $read_aligner = 'maq0_6_3';
my $pp_name = 'testing';

diag('test command create for a processing profile reference alignments');
my $create_pp_command= Genome::Model::Command::Create::ProcessingProfile::ReferenceAlignment->create(
     indel_finder          => $indel_finder,
     dna_type              => $dna_type,
     align_dist_threshold  => $align_dist_threshold,
     reference_sequence    => $reference_sequence,
     genotyper             => $genotyper ,
     read_aligner          => $read_aligner,
     profile_name          => $pp_name,
     bare_args => [],
 );


# check and create the processing profile
isa_ok($create_pp_command,'Genome::Model::Command::Create::ProcessingProfile::ReferenceAlignment');
ok($create_pp_command->execute(), 'execute processing profile create');     

# Get it and make sure there is one
my @processing_profiles = Genome::ProcessingProfile::ReferenceAlignment->get(name => $pp_name);
is(scalar(@processing_profiles),1,'expected one processing profile');

# check the type
my $pp = $processing_profiles[0];
isa_ok($pp ,'Genome::ProcessingProfile::ReferenceAlignment');

# Test the properties were set and the accessors functionality
is($pp->indel_finder_name,$indel_finder,'processing profile indel_finder accessor');
is($pp->dna_type,$dna_type,'processing profile dna_type accessor');
is($pp->align_dist_threshold,$align_dist_threshold,'processing profile align_dist_threshold accessor');
is($pp->reference_sequence_name,$reference_sequence,'processing profile reference_sequence accessor');
is($pp->genotyper_name,$genotyper,'processing profile genotyper accessor');
is($pp->read_aligner_name,$read_aligner,'processing profile read_aligner accessor');
is($pp->name,$pp_name,'processing profile name accessor');


diag('test command create for a genome model');
my $create_command = Genome::Model::Command::Create::Model->create(
                                                                   model_name              => $model_name,
                                                                   subject_name            => $subject_name,
                                                                   processing_profile_name => $pp_name,
                                                                   bare_args               => [],
                                                               );
isa_ok($create_command,'Genome::Model::Command::Create::Model');
my $result = $create_command->execute();
ok($result, 'execute genome-model create');

my $genome_model_id = $result->id;

my @models = Genome::Model->get($genome_model_id);
is(scalar(@models),1,'expected one model');

my $model = $models[0];
isa_ok($model,'Genome::Model');

is($model->genome_model_id,$genome_model_id,'model genome_model_id accessor');
is($model->indel_finder_name,$indel_finder,'model indel_finder accessor');
is($model->name,$model_name,'model model_name accessor');
is($model->subject_name,$subject_name,'model subject_name accessor');
is($model->dna_type,$dna_type,'model dna_type accessor');
is($model->align_dist_threshold,$align_dist_threshold,'model align_dist_threshold accessor');
is($model->reference_sequence_name,$reference_sequence,'model reference_sequence accessor');
is($model->genotyper_name,$genotyper,'model genotyper accessor');
is($model->read_aligner_name,$read_aligner,'model read_aligner accessor');

UR::Context->_sync_databases(); 


diag('test create for a genome model object');
$model_name = 'model_name_here';
$subject_name = 'subject_name_here';
my $obj_create = Genome::Model::Command::Create::Model->create(
                                                               model_name => $model_name,
                                                               subject_name => $subject_name,
                                                               processing_profile_name   => $pp->name,
                                                               bare_args => [],
                                                           );
isa_ok($obj_create,'Genome::Model::Command::Create::Model');
ok($obj_create->execute,'execute model create');

my $obj = Genome::Model->get(name => $model_name);
ok($obj, 'creation worked');
isa_ok($obj ,'Genome::Model::ReferenceAlignment');

# Test the accessors through the processing profile
diag('Test accessing model for processing profile properties...');
is($obj->indel_finder_name,$indel_finder,'indel_finder accessor');
is($obj->dna_type,$dna_type,'dna_type accessor');
is($obj->align_dist_threshold,$align_dist_threshold,'align_dist_threshold accessor');
is($obj->reference_sequence_name,$reference_sequence,'reference_sequence accessor');
is($obj->genotyper_name,$genotyper,'genotyper accessor');
is($obj->read_aligner_name,$read_aligner,'read_aligner accessor');
is($obj->name,$model_name,'name accessor');
is($obj->type_name,'reference alignment','type name accessor');

# test the model accessors
diag('Test accessing model for model properties...');
is($obj->name,$model_name,'model name accessor');
is($obj->subject_name,$subject_name,'subject name accessor');
is($obj->processing_profile_id,$pp->id,'processing profile id accessor');

diag('subclassing tests - test create for a processing profile object of each subclass');

# Test creation for the corresponding models
diag('subclassing tests - test create for a genome model object of each subclass');

#reference alignment
test_model_from_params(
                       model_name => 'reference alignment',
                   );
#de novo sanger
test_model_from_params(
                       model_name => 'de novo sanger',
                   );
#imported reference sequence
test_model_from_params(
                       model_name => 'imported reference sequence',
                   );

#watson
test_model_from_params(
                       model_name => 'watson',
                   );
#venter
test_model_from_params(
                       model_name => 'venter',
                   );

#micro array
test_model_from_params(
                       model_name => 'micro array',
                   );

#micro array illumina
test_model_from_params(
                       model_name => 'micro array illumina',
                   );

#micro array affymetrix
test_model_from_params(
                       model_name => 'micro array affymetrix',
                   );

#assembly
test_model_from_params(
                       model_name => 'assembly',
                       subject_name => $subject_name,
                   );
exit;

sub delete_model {
    my $model = shift;
    my $archive_file = $model->resolve_archive_file;
    ok($model->delete,'delete model');
    ok(unlink($archive_file),'remove archive file');
}

sub test_model_from_params {
    my %params = @_;

    my @words = split(/ /,$params{model_name});
    my @uc_words = map { ucfirst($_)  } @words;
    my $class = join('',@uc_words);
    $params{bare_args} = [];
    $params{processing_profile_name} = $class;

    my %pp_params = (
                     type_name => $params{model_name},
                     name => $params{processing_profile_name},
                 );

    my $pp = Genome::ProcessingProfile->create(%pp_params);
    isa_ok($pp,'Genome::ProcessingProfile::'. $class);

    my $create_command = Genome::Model::Command::Create::Model->create(%params);
    isa_ok($create_command,'Genome::Model::Command::Create::Model');
    ok($create_command->execute, 'create command execution successful');

    my $model = Genome::Model->get(name => $params{model_name},);
    ok($model, 'creation worked for '. $params{model_name} .' alignment model');
    isa_ok($model,'Genome::Model::'.$class);
    SKIP: {
        skip 'no model to delete', 2 if !$model;
        delete_model($model);
    }
}
