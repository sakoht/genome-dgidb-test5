#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

use_ok("Genome::Model::Tools::Allpaths::DeNovoAssemble");

#make temp test dir
my $temp_dir = Genome::Sys->create_temp_directory();
ok(-d $temp_dir, "Temp test dir created");

my $data_dir = "fake";
my $create = Genome::Model::Tools::Allpaths::DeNovoAssemble->create(
    version => 39099,
    pre => $temp_dir,
    ploidy => 1,
    in_group_file => $data_dir."/in_group.csv",
    in_libs_file => $data_dir."/in_libs.csv",
    run => "aRun",
    sub_dir => "aSubDir",
    overwrite => 1,
    reference_name => "sampleReference",
);
ok( $create, "Created gmt allpaths de-novo-assemble");

#TODO: I haven't been able to create test data that will assemble
#fast enough to put in a perl test.  It may be possible.

done_testing();

