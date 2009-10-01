#!/gsc/bin/perl

use strict;
use warnings;

use File::Path;
use Test::More;

use above 'Genome';

BEGIN {
    if (`uname -a` =~ /x86_64/) {
        plan tests => 19;
    } else {
        plan skip_all => 'Must run on a 64 bit machine';
    }
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    use_ok('Genome::InstrumentData::Solexa');
    use_ok('Genome::InstrumentData::Command::Align::Maq');
}


my $gerald_directory = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Align-Maq/test_sample_name';

# Existing
my $instrument_data = Genome::InstrumentData::Solexa->create_mock(
                                                                  id => '-123456',
                                                                  sequencing_platform => 'solexa',
                                                                  sample_name => 'test_sample_name',
                                                                  run_name => 'test_run_name',
                                                                  subset_name => 4,
                                                                  run_type => 'Paired End Read 2',
                                                                  gerald_directory => $gerald_directory,
                                                              );
isa_ok($instrument_data,'Genome::InstrumentData::Solexa');
$instrument_data->set_always('sample_type','dna');
$instrument_data->set_always('resolve_quality_converter','sol2sanger');
$instrument_data->set_always('is_paired_end',1);
ok($instrument_data->is_paired_end,'instrument data is paired end');



my $fake_allocation = Genome::Disk::Allocation->__define__(
                                                       disk_group_name => 'info_alignments',
                                                       group_subdirectory => 'info',
                                                       mount_path => '/gscmnt/sata828',
                                                       allocation_path => 'alignment_data/maq0_7_1/refseq-for-test/test_run_name/4_-123456',
                                                       allocator_id => '-123457',
                                                       kilobytes_requested => 100000,
                                                       kilobutes_used => 0,
                                                       owner_id => $instrument_data->id,
                                                       owner_class_name => 'Genome::InstrumentData::Solexa',
                                                   );
isa_ok($fake_allocation,'Genome::Disk::Allocation');
$instrument_data->set_list('allocations',$fake_allocation);

my $alignment = Genome::InstrumentData::Alignment::Maq->create(
                                                          instrument_data_id => $instrument_data->id,
                                                          aligner_name => 'maq',
                                                          aligner_version => '0.7.1',
                                                          reference_name => 'refseq-for-test',
                                                      );

# TODO: create mock event or use some fake event for logging

# once to find old data
ok($alignment->find_or_generate_alignment_data,'found old alignment data');

my $dir = $alignment->alignment_directory;
ok($dir, "alignments found/generated");
ok(-d $dir, "result is a real directory");

#No need to commit because we short cut


$instrument_data = Genome::InstrumentData::Solexa->create_mock(
                                                               id => '-123458',
                                                               sequencing_platform => 'solexa',
                                                               sample_name => 'test_sample_name',
                                                               run_name => 'test_run_name',
                                                               subset_name => 4,
                                                               run_type => 'Paired End Read 2',
                                                               gerald_directory => '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Align-Maq/test_sample_name',
                                                           );
my @fastq_files = glob($instrument_data->gerald_directory.'/*.txt');
$instrument_data->set_always('sample_type','dna');
$instrument_data->set_always('is_paired_end',1);
$instrument_data->set_always('resolve_quality_converter','sol2phred');
$instrument_data->set_always('class','Genome::InstrumentData::Solexa');

my $tmp_dir = File::Temp::tempdir('Align-Maq-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my $tmp_allocation = Genome::Disk::Allocation->create_mock(
                                                           id => '-123459',
                                                           disk_group_name => 'info_alignments',
                                                           group_subdirectory => 'test',
                                                           mount_path => '/tmp/mount_path',
                                                           allocation_path => 'alignment_data/maq0_7_1/refseq-for-test/test_run_name/4_-123458',
                                                           allocator_id => '-123459',
                                                           kilobytes_requested => 100000,
                                                           kilobytes_used => 0,
                                                           owner_id => $instrument_data->id,
                                                           owner_class_name => 'Genome::InstrumentData::Solexa',
                                                       );
$tmp_allocation->mock('absolute_path',
                      sub { return $tmp_dir; }
                  );
$tmp_allocation->set_always('reallocate',1);
$tmp_allocation->set_always('deallocate',1);
isa_ok($tmp_allocation,'Genome::Disk::Allocation');
$instrument_data->set_list('allocations',$tmp_allocation);
$instrument_data->set_list('fastq_filenames',@fastq_files);
$instrument_data->set_always('calculate_alignment_estimated_kb_usage',10000);

$alignment = Genome::InstrumentData::Alignment->create(
                                                       instrument_data_id => $instrument_data->id,
                                                       aligner_name => 'maq',
                                                       aligner_version => '0.7.1',
                                                       reference_name => 'refseq-for-test',
                                                   );

# once to make new data
ok($alignment->find_or_generate_alignment_data,'generated new alignment data for paired end data');
my $dir2 = $alignment->alignment_directory;
ok($dir2, "alignments found/generated");
ok(-d $dir2, "result is a real directory");
ok($alignment->remove_alignment_directory,'removed alignment directory '. $dir2);
ok(! -e $dir2, 'alignment directory does not exist');


#Run paired end as fragment
$tmp_allocation->allocation_path('alignment_data/maq0_7_1/refseq-for-test/test_run_name/fragment/4_-123458');
$tmp_dir = File::Temp::tempdir('Align-Maq-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
$instrument_data->set_list('fastq_filenames',$fastq_files[0]);
$alignment = Genome::InstrumentData::Alignment->create(
                                                       instrument_data_id => $instrument_data->id,
                                                       aligner_name => 'maq',
                                                       aligner_version => '0.7.1',
                                                       reference_name => 'refseq-for-test',
                                                       force_fragment => 1,
                                                   );
ok($alignment->find_or_generate_alignment_data,'generated new alignment data for paired end data as fragment alignment');
my $dir3 = $alignment->alignment_directory;
ok($dir3, "alignments found/generated");
ok(-d $dir3, "result is a real directory");
ok($alignment->remove_alignment_directory,'removed alignment directory '. $dir3);
ok(! -e $dir3, 'alignment directory does not exist');

exit;
