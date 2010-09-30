#!/usr/bin/env perl
use strict;
use warnings;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = "1";
$ENV{UR_DBI_NO_COMMIT} = "1";
use above "Genome";
use Test::More tests => 14;
use File::Temp;
use Genome::Sample;

my $s = Genome::Sample->get(2824113551);

ok($s, 'loaded sample data');

my $library_name = "Pooled_Library-2010-02-10_2";

my $dummy_id = UR::DataSource->next_dummy_autogenerated_id -1;

my $source_dir = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Command-Import-Fastq/s_5_1_sequence.txt,/gsc/var/cache/testsuite/data/Genome-InstrumentData-Command-Import-Fastq/s_5_2_sequence.txt';
my $wrong_name =  '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Command-Import-Fastq/sequence_funny_name.txt';
my $library = Genome::Library->get(name => $library_name);
my $sample = Genome::Sample->get(id => $library->sample_id);
my $sample_name = $sample->name;
ok($sample, "found sample $sample_name")
    or die "exiting because the sample does not exist";

my $tmp_dir = File::Temp::tempdir('Genome-InstrumentData-Commnd-Import-Fastq-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my $tmp_allocation = Genome::Disk::Allocation->__define__(
                                                           id => '-123459',
                                                           disk_group_name => 'info_alignments',
                                                           group_subdirectory => 'test',
                                                           mount_path => '/tmp/mount_path',
                                                           allocation_path => 'fastq_data/imported/-830001',
                                                           allocator_id => '-123459',
                                                           kilobytes_requested => 100000,
                                                           kilobytes_used => 0,
                                                           owner_id => $dummy_id-100,
                                                           owner_class_name => 'Genome::InstrumentData::Imported',
                                                       );

no warnings;
*Genome::Disk::Allocation::absolute_path = sub { return $tmp_dir };
*Genome::Disk::Allocation::reallocate = sub { 1 };
*Genome::Disk::Allocation::deallocate = sub { 1 };
use warnings;

isa_ok($tmp_allocation,'Genome::Disk::Allocation'); 

my $cmd = Genome::InstrumentData::Command::Import::Fastq->create(
    sample_name => $sample_name,
    source_data_files => $source_dir,
    allocation =>  $tmp_allocation,
    import_format => 'sanger fastq',
    subset_name => 5,
    is_paired_end => 1,
);

ok($cmd, "constructed an import command");

my @errors = $cmd->__errors__;

is(scalar(@errors),0, "no errors in cmd");

my $result = $cmd->execute();

ok($result, "execution was successful");

my $i = Genome::InstrumentData::Imported->get(  
    sample_name => $sample_name, 
    library_id => $library->id,
    sequencing_platform => 'solexa',      
    import_format => 'sanger fastq',
    
);

ok($i, "found Imported instrument data")
    or die "Did not find Imported Instrument Data using sample_name = $sample_name";

my $disk = Genome::Disk::Allocation->get(owner_class_name => $i->class, owner_id => $i->id, allocator_id => -123459);

ok($disk, "found an allocation owned by the new instrument data");

my $owner_class = $disk->owner_class_name;

is($owner_class, "Genome::InstrumentData::Imported", "allocation belongs to  G::I::I::Fastq");

is($disk->owner_id, $i->id, "allocation owner ID matches imported instrument data id");

ok(-e $i->data_directory, "output directory is present");

is($i->library_id,$library->id,"library_id matches");

$i->delete;

my $cmd2 = Genome::InstrumentData::Command::Import::Fastq->create(
    library_name => $library_name,
    source_data_files => $wrong_name, 
    allocation => $tmp_allocation,
    import_format => 'sanger fastq',
    is_paired_end => 0,
);

ok($cmd2, "Constructed import command for faulty-fastq filename - OK");

eval{ 
    $cmd2->execute();
};

ok($@, "Execution did not proceed for a bad filname. This is Good.");
