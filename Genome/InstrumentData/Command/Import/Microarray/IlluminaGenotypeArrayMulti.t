#!/usr/bin/env perl
use strict;
use warnings;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = "1";
$ENV{UR_DBI_NO_COMMIT} = "1";
use above "Genome";
#use Test::More skip_all => "under development";
#__END__


#This test does not check to see if models are successfully defined.
#use Test::More skip_all => "This test was mysteriously broken. I am still tracking down the cause. -rlong";
use Test::More tests => 4;
use File::Temp;
use Data::Dumper;
use File::Find;

my $sample_name = 'multiple'; 
my $source_dir = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Command-Import-Microarray/test_files/multi'; 
#my $source_dir = '/gscmnt/sata422/info/medseq/brc_wgs/snp_array/Data_Infinium1MOmni_BRC-samples-only_20100412';
ok (-d $source_dir, "our example directory exists");

my $tmp_dir = File::Temp::tempdir('Genome-InstrumentData-Command-Import-Microarray-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my @tmp_allocations;
my @dummy_ids;
my $count;
my $id = -123458;
my $autoid = UR::DataSource->next_dummy_autogenerated_id -1;
Genome::Disk::Allocation->__define__(
    id => ($id)."",
    disk_group_name => 'info_alignments',
    group_subdirectory => 'test',
    mount_path => '/tmp/mount_path',
    allocation_path => 'microarray_data/imported/'.$autoid,
    kilobytes_requested => 1000000,
    kilobytes_used => 0,
    owner_id => $autoid,
    owner_class_name => 'Genome::InstrumentData::Imported',
);

no warnings;
*Genome::Disk::Allocation::absolute_path = sub { return $tmp_dir };
*Genome::Disk::Allocation::reallocate = sub { 1 };
*Genome::Disk::Allocation::deallocate = sub { 1 };
use warnings;

my $cmd = Genome::InstrumentData::Command::Import::Microarray::IlluminaGenotypeArrayMulti->create(
    original_data_path => $source_dir,
);

ok($cmd, "constructed an import command");


my @errors = $cmd->__errors__;

is(scalar(@errors),0, "no errors in cmd");

my $result = $cmd->execute();

ok($result, "execution was successful");

#$DB::single=1;
#my $build = Genome::Model::Build::Command::Start->execute( model_identifier => -830003 );

#ok($build, "build started");

#sleep 5;

#print "finished sleeping, proceeding to remove build\n";

#my $remove = Genome::Model::Build::Command::Remove->execute( build_id => -830004 );


#ok($remove, "build removed");
