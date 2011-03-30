#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";

use Data::Dumper 'Dumper';
use File::Slurp;
use File::Temp;
use Genome::Model::Command::Define::GenotypeMicroarray;
use Test::More;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}



#$ENV{UR_DBI_NO_COMMIT} = 1;
#$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

no warnings;
*Genome::Report::Email::send_report = sub{ return 1; }; # so we don't get emails
*UR::Context::commit = sub{ return 1; }; # NO_COMMIT is not working in G:M:C:Services:Build:Run and actually commits
use warnings;

use_ok("Genome::Model::Command::Define::GenotypeMicroarray") or die;

my $tempdir = File::Temp::tempdir(CLEANUP => 1);
my $temp_wugc = $tempdir."/genotype-microarray-test.wugc";

my $ref_pp = Genome::ProcessingProfile::ImportedReferenceSequence->create(name => 'test_ref_pp');
my $ref_model = Genome::Model::ImportedReferenceSequence->create(
    name                => 'test_ref_sequence',
    processing_profile  => $ref_pp,
    subject_class_name  => 'Genome::Taxon',
    subject_id          => 1653198737,
);
#my $rbuild = Genome::Model::Build::ImportedReferenceSequence->create(
    #name            => 'test_ref_sequence_build',
    #model           => $ref_model,
    #fasta_file      => 'nofile', 
    #data_directory  => $tempdir,
    #version         => "37",
#);
my $rbuild = Genome::Model::Build::ImportedReferenceSequence->get(name => "NCBI-human-build36");
ok($rbuild, 'got reference sequence build');

my $test_model_name = "genotype-ma-test-".$ENV{USER}."-".$$;
$test_model_name ='H_KA-123172-S.3576';
my $ppid = 2166945;
my $ppname = 'illumina wugc';


#write_file($temp_wugc,'1\t72017\tAA\n1\t311622\tAA\n1\t314893\t--\n');
write_file($temp_wugc,"1\t72017\t72017\tA\tA\tref\tref\tref\tref\n1\t311622\t311622\tG\tA\tref\tSNP\tref\tSNP\n1\t314893\t--\n");

# attempt to define command w/o reference is an error
my $gm = Genome::Model::Command::Define::GenotypeMicroarray->create(
    processing_profile_name => $ppname ,
    subject_name            => $test_model_name, 
    model_name              => $test_model_name .".test",
    data_directory          => $tempdir,
    file                    => $temp_wugc ,
);
$gm->dump_status_messages(1);
ok(!$gm->execute(), 'attempt to define command w/o reference is an error');
$gm->delete;

# success
$gm = Genome::Model::Command::Define::GenotypeMicroarray->create(
    processing_profile_name => $ppname ,
    subject_name            => $test_model_name, 
    model_name              => $test_model_name .".test",
    data_directory          => $tempdir,
    reference               => $rbuild,
    file                    => $temp_wugc ,
);
$gm->dump_status_messages(1);
ok($gm->execute(),'define model');

# check for the model with the name
my $model = Genome::Model->get(name => $test_model_name.".test");
is($model->name,$test_model_name.".test", 'expected test model name retrieved');

# build
my $build = Genome::Model::Build->get(model_id => $model->id);
ok($build, 'we got a build object back');
is($build->status, 'Succeeded', 'build is succeeded');

# check the build directory, check the contents for the file...
ok(-d $build->data_directory, 'data directory exists');
my $orig_contents = read_file($temp_wugc);
my $dest_contents = read_file($build->data_directory."/formatted_genotype_file_path.genotype");
#formatted_genotype_file_path.genotype
is($dest_contents,$orig_contents,'original and copied files match');

ok(-s $build->snvs_bed("v1"), "gold snp bed file exists");

# let us nuke the build and model...
system("rm -rf ".$model->data_directory);
$build->delete;
$model->delete;

done_testing(10);
