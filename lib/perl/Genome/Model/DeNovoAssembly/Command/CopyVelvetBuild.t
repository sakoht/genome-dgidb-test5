#!/gsc/bin/perl

use strict;
use warnings;

use above 'Genome';
use Test::More;
use File::Basename;
use Genome::Model::DeNovoAssembly::Test;

use_ok ('Genome::Model::DeNovoAssembly::Command::CopyVelvetBuild');

#get test model
my $model = Genome::Model::DeNovoAssembly::Test->get_mock_model(
    sequencing_platform => 'solexa',
    assembler_name => 'velvet',
    );
ok( $model, "Got mock de-novo-assembly model" );

#test build
my $build = Genome::Model::DeNovoAssembly::Test->get_mock_build(
    model => $model,
    use_example_directory => 1,
    );
ok ( $build, "Got mock de-novo-assembly build" );

#create tool
my $temp_dir = Genome::Utility::FileSystem->create_temp_directory();
ok ( -d $temp_dir, "Created temp test directory");

my $tool = Genome::Model::DeNovoAssembly::Command::CopyVelvetBuild->create (
    build_id => $build->id,
    to => $temp_dir,
    );

#check that all velvet output files exist
for my $file ( $tool->_velvet_files_to_link ) {
    ok (-e $build->data_directory."/$file", "$file exists in test dir"); 
}

#execute tool
ok ($tool->execute, "Executed tool successfully");

#check that file got linked
for my $file ( $tool->_velvet_files_to_link ) {
    ok (-l $temp_dir."/$file", "$file has been linked");
}

#check everything in edit_dir got copied
for my $file ( glob( $build->data_directory."/edit_dir/*" ) ) {
    my $file_name = basename ($file);
    ok (-e $temp_dir."/edit_dir/$file_name", "$file has been copied to edit_dir");
}

done_testing();

exit;
