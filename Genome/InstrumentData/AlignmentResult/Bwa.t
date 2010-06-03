#!/gsc/bin/perl

use strict;
use warnings;

use File::Path;
use Test::More;
use Sys::Hostname;

use above 'Genome';

BEGIN {
    if (`uname -a` =~ /x86_64/) {
        plan tests => 24;
    } else {
        plan skip_all => 'Must run on a 64 bit machine';
    }
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    use_ok('Genome::InstrumentData::Solexa');
    use_ok('Genome::InstrumentData::Command::Align::Bwa');
}

#
# Gather up versions for the tools used herein
#
#
###############################################################################

my $samtools_version = Genome::Model::Tools::Sam->default_samtools_version;
my $picard_version = Genome::Model::Tools::Sam->default_picard_version;

my $bwa_version = Genome::Model::Tools::Bwa->default_bwa_version;
my $bwa_label   = 'bwa'.$bwa_version;
$bwa_label =~ s/\./\_/g;

my $reference_model = Genome::Model::ImportedReferenceSequence->get(name => 'TEST-human');
ok($reference_model, "got reference model");

my $reference_build = $reference_model->build_by_version('1');
ok($reference_build, "got reference build");

#
# Define a fake alignment, to test the shortcut feature
#
###########################################################
$DB::single = 1;
use Genome::InstrumentData::AlignmentResult::Bwa;
my $sr = Genome::InstrumentData::AlignmentResult::Bwa->__define__(
                 'id' => -8765432,
                 'output_dir' => "/gscmnt/sata828/info/alignment_data/$bwa_label/refseq-for-test/test_run_name/4_-123456",
                 #'software' =>  'Genome::InstrumentData::Aligner::Bwa' ,
                 #'software_version' => $bwa_version,
                 'instrument_data_id' => '-123456',
                 #'result_class_name' => 'Genome::InstrumentData::AlignmentResult::Bwa',
                 subclass_name => 'Genome::InstrumentData::AlignmentResult::Bwa',
                 module_version => '12345',
                 aligner_name=>'bwa',
                 aligner_version=>$bwa_version,
                 samtools_version=>$samtools_version,
                 picard_version=>$picard_version,
                 reference_build => $reference_build, 
);

isa_ok($sr, 'Genome::SoftwareResult');

## Defien the instrument data for it

my $gerald_directory = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Align-Maq/test_sample_name';

my $instrument_data = Genome::InstrumentData::Solexa->create_mock(
                                                                  id => '-123456',
                                                                  sequencing_platform => 'solexa',
                                                                  flow_cell_id => '12345',
                                                                  lane => '1',
                                                                  seq_id => '-123456',
                                                                  median_insert_size => '22',
                                                                  sample_name => 'test_sample_name',
                                                                  library_name => 'test_sample_name-lib1',
                                                                  run_name => 'test_run_name',
                                                                  subset_name => 4,
                                                                  run_type => 'Paired End Read 2',
                                                                  gerald_directory => $gerald_directory,
                                                              );



my @in_fastq_files = glob($instrument_data->gerald_directory.'/*.txt');
$instrument_data->set_list('fastq_filenames',@in_fastq_files);
isa_ok($instrument_data,'Genome::InstrumentData::Solexa');
$instrument_data->set_always('sample_type','dna');
$instrument_data->set_always('sample_id','2791246676');
$instrument_data->set_always('is_paired_end',1);
ok($instrument_data->is_paired_end,'instrument data is paired end');
$instrument_data->set_always('calculate_alignment_estimated_kb_usage',10000);
$instrument_data->set_always('resolve_quality_converter','sol2sanger');
$instrument_data->set_always('run_start_date_formatted','Fri Jul 10 00:00:00 CDT 2009');


#
# Fake an allocation for the alignment output
#########

my $fake_allocation = Genome::Disk::Allocation->__define__(
                                                       disk_group_name => 'info_alignments',
                                                       group_subdirectory => 'info',
                                                       mount_path => '/gscmnt/sata828',
                                                       allocation_path => 'alignment_data/'.$bwa_label.'/refseq-for-test/test_run_name/4_-123456',
                                                       allocator_id => '-123457',
                                                       kilobytes_requested => 100000,
                                                       kilobytes_used => 0,
                                                       owner_id => $instrument_data->id,
                                                       owner_class_name => 'Genome::InstrumentData::Solexa',
                                                   );

isa_ok($fake_allocation,'Genome::Disk::Allocation');
$instrument_data->set_list('allocations',$fake_allocation);

#
# Step 1: Attempt to create an alignment that's already been created 
# ( the one we defined up at the top of the test case )
#
# This ought to fail to return anything
####################################################

my $bad_alignment;
$bad_alignment = Genome::InstrumentData::AlignmentResult::Bwa->create(
                                                          instrument_data_id => $instrument_data->id,
                                                          aligner_name => 'bwa',
                                                          aligner_version => $bwa_version,
                                                          samtools_version => $samtools_version,
                                                          picard_version => $picard_version,
                                                          reference_build => $reference_build, 
                                                      );
ok(!$bad_alignment, "this should have returned undef, for attempting to create an alignment that is already created!");
ok(Genome::InstrumentData::AlignmentResult::Bwa->error_message =~ m/already have one/, "the exception is what we expect to see");


#
# Step 2: Attempt to get an alignment that's already created
#
#################################################
my $alignment = Genome::InstrumentData::AlignmentResult::Bwa->get(
                                                          instrument_data_id => $instrument_data->id,
                                                          aligner_name => 'bwa',
                                                          aligner_version => $bwa_version,
                                                          samtools_version => $samtools_version,
                                                          picard_version => $picard_version,
                                                          reference_build => $reference_build, 
                                                          );
ok($alignment, "got an alignment object");

# TODO: create mock event or use some fake event for logging

# once to find old data
my $adir = $alignment->alignment_directory;
my @list = <$adir/*>;

ok($alignment, "Created Alignment");
my $dir = $alignment->alignment_directory;
ok($dir, "alignments found/generated");
ok(-d $dir, "result is a real directory");
ok(-s $dir."/all_sequences.bam", "found a bam file in there");


# create another bogus instrument data and allocation

$instrument_data = Genome::InstrumentData::Solexa->create_mock(
                                                               id => '-123458',
                                                               flow_cell_id => '12345',
                                                               lane => '1',
                                                               seq_id => '-123458',
                                                               median_insert_size => '22',
                                                               sequencing_platform => 'solexa',
                                                               sample_name => 'test_sample_name',
                                                               library_name => 'test_sample_name-lib1',
                                                               run_name => 'test_run_name',
                                                               subset_name => 4,
                                                               run_type => 'Paired End Read 2',
                                                               gerald_directory => '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Align-Maq/test_sample_name',
                                                           );
my @fastq_files = glob($instrument_data->gerald_directory.'/*.txt');
$instrument_data->set_always('sample_type','dna');
$instrument_data->set_always('is_paired_end',1);
$instrument_data->set_always('class','Genome::InstrumentData::Solexa');
$instrument_data->set_always('resolve_quality_converter','sol2sanger');
$instrument_data->set_always('run_start_date_formatted','Fri Jul 10 00:00:00 CDT 2009');
$instrument_data->set_always('sample_id','2791246676');

my $tmp_dir = File::Temp::tempdir('Align-Bwa-XXXXX', DIR => Genome::Utility::FileSystem->base_temp_directory, CLEANUP => 1);
my $staging_base = sprintf("alignment-%s-%s-%s", hostname(), $ENV{'USER'}, $$);
my $tmp_allocation = Genome::Disk::Allocation->__define__(
                                                           id => '-123459',
                                                           disk_group_name => 'info_alignments',
                                                           group_subdirectory => 'test',
                                                           mount_path => $tmp_dir,
                                                           allocation_path => 'alignment_data/'.$bwa_label.'/refseq-for-test/test_run_name/4_-123458/' . $staging_base,
                                                           allocator_id => '-123459',
                                                           kilobytes_requested => 100000,
                                                           kilobytes_used => 0,
                                                           owner_id => $instrument_data->id,
                                                           owner_class_name => 'Genome::InstrumentData::Solexa',
                                                       );
mkpath($tmp_allocation->absolute_path);

# manage reallocation since we're not actually doing a real allocation
*Genome::Disk::Allocation::reallocate = sub { print "I would reallocate here!!"};

isa_ok($tmp_allocation,'Genome::Disk::Allocation');
$instrument_data->set_list('fastq_filenames',@fastq_files);
$instrument_data->set_always('calculate_alignment_estimated_kb_usage',10000);
$instrument_data->set_always('resolve_quality_converter','sol2sanger');

#
#
# attempt to do another alignment
#
#
##################

$alignment = Genome::InstrumentData::AlignmentResult::Bwa->create(
                                                       instrument_data_id => $instrument_data->id,
                                                       samtools_version => $samtools_version,
                                                       picard_version => $picard_version,
                                                       aligner_version => $bwa_version,
                                                       aligner_name => 'bwa',
                                                       reference_build => $reference_build, 
                                                   );

# once to make new data
$adir = $alignment->alignment_directory;
@list = <$adir/*>;

ok($alignment, "Created Alignment");
$dir = $alignment->alignment_directory;
ok($dir, "alignments found/generated");
ok(-d $dir, "result is a real directory");
ok(-s $dir . "/all_sequences.bam", "result has a bam file");

# clear out the fastqs so we re-unpack them again
note "Remove sanger_fastq files:\n";
for (@{$alignment->_sanger_fastq_pathnames}) {
    print "$_\n";
    unlink($_);
}

my $base_tempdir = Genome::Utility::FileSystem->base_temp_directory;
for (glob($base_tempdir . "/*")) {
    File::Path::rmtree($_);
}

#Run paired end as fragment
$tmp_allocation->allocation_path('alignment_data/'.$bwa_label.'/refseq-for-test/test_run_name/fragment/4_-123458/' . $staging_base);
mkpath($tmp_allocation->absolute_path);
$instrument_data->set_list('fastq_filenames',$fastq_files[0]);
$alignment = Genome::InstrumentData::AlignmentResult::Bwa->create(
                                                       instrument_data_id => $instrument_data->id,
                                                       aligner_name => 'bwa',
                                                       samtools_version => $samtools_version,
                                                       picard_version => $picard_version,
                                                       aligner_version => $bwa_version,
                                                       reference_build => $reference_build, 
                                                       force_fragment => 1,
                                                   );

ok($alignment, "Created Alignment");
$dir = $alignment->alignment_directory;
ok($dir, "alignments found/generated");
ok(-d $dir, "result is a real directory");
ok(-s $dir . "/all_sequences.bam", "result has a bam file");
