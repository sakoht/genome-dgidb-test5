#!/gsc/bin/perl

use strict;
use warnings;

use File::Path;
use Test::More;
use Sys::Hostname;

use above 'Genome';

BEGIN {
    if (`uname -a` =~ /x86_64/) {
        plan tests => 25;
    } 
    else {
        plan skip_all => 'Must run on a 64 bit machine';
    }
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    use_ok('Genome::InstrumentData::Solexa');
    use_ok('Genome::InstrumentData::Command::Align::Maq');
}

my $samtools_version = Genome::Model::Tools::Sam->default_samtools_version;
my $picard_version   = Genome::Model::Tools::Picard->default_picard_version;

my $reference_model = Genome::Model::ImportedReferenceSequence->get(name => 'TEST-human');
ok($reference_model, "got reference model");

my $reference_build = $reference_model->build_by_version('1');
ok($reference_build, "got reference build");

# The following line is to pretend to add a software-result record to
# DB and make the codes following this taking it as already existing

my $sr = Genome::InstrumentData::AlignmentResult::Maq->__define__(
    id                 => -87654321,
    output_dir         => '/gscmnt/sata828/info/alignment_data/maq0_7_1/refseq-for-test/test_run_name/4_-123457',
    instrument_data_id => '-123457',
    subclass_name      => 'Genome::InstrumentData::AlignmentResult::Maq',
    module_version     => '12345',
    aligner_name       => 'maq',
    aligner_version    => '0.7.1',
    samtools_version   => $samtools_version,
    picard_version     => $picard_version,
    reference_build    => $reference_build, 
);

isa_ok($sr, 'Genome::SoftwareResult');

my $gerald_directory = '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Align-Maq/test_sample_name';

my %ins_data_params = (
    id                  => '-123457',
    sequencing_platform => 'solexa',
    sample_name         => 'test_sample_name',
    library_name        => 'test_sample_name-lib1',
    run_name            => 'test_run_name',
    subset_name         => 4,
    run_type            => 'Paired End Read 2',
    gerald_directory    => $gerald_directory,
    flow_cell_id        => '33G',
    lane                => '4',
);

my $instrument_data = Genome::InstrumentData::Solexa->create_mock(%ins_data_params);

my @fastq_files = glob($instrument_data->gerald_directory.'/*.txt');
$instrument_data->set_list('dump_sanger_fastq_files', @fastq_files);                                         
isa_ok($instrument_data,'Genome::InstrumentData::Solexa');
$instrument_data->set_always('sample_type','dna');
$instrument_data->set_always('resolve_quality_converter','sol2sanger');
$instrument_data->set_always('run_start_date_formatted','Fri Jul 10 00:00:00 CDT 2009');
$instrument_data->set_always('sample_id','2791246676');
$instrument_data->set_always('is_paired_end',1);
ok($instrument_data->is_paired_end,'instrument data is paired end');

my %alloc_params = (
    disk_group_name     => 'info_alignments',
    group_subdirectory  => 'info',
    mount_path          => '/gscmnt/sata828',
    allocation_path     => 'alignment_data/maq0_7_1/refseq-for-test/test_run_name/4_-123457',
    allocator_id        => '-1234567',
    kilobytes_requested => 100000,
    kilobytes_used      => 0,
    owner_id            => $instrument_data->id,
    owner_class_name    => 'Genome::InstrumentData::Solexa',
);

my $fake_allocation = Genome::Disk::Allocation->__define__(%alloc_params);

isa_ok($fake_allocation,'Genome::Disk::Allocation');
$instrument_data->set_list('allocations',$fake_allocation);


################################Test 1: Fail to create a new maq alignment due to its existing##########################

# Attempt to create an alignment that is already been created 
# ( the one we defined up at the top of the test case )
# This ought to fail to return anything

my %align_param = (
    instrument_data_id => $instrument_data->id,
    aligner_name       => 'maq',
    aligner_version    => '0.7.1',
    samtools_version   => $samtools_version,
    picard_version     => $picard_version,
    reference_build    => $reference_build, 
);

my $bad_alignment;
$bad_alignment = Genome::InstrumentData::AlignmentResult::Maq->create(%align_param);
ok(!$bad_alignment, "this should have returned undef, for attempting to create an alignment that is already created!");
ok(Genome::InstrumentData::AlignmentResult::Maq->error_message =~ m/already have one/, "the exception is what we expect to see");

# Attempt to get an alignment that is already created

my $alignment = Genome::InstrumentData::AlignmentResult::Maq->get(%align_param);
ok($alignment, "got an alignment object");

# Get old data

my $dir = $alignment->alignment_directory;
ok($dir, "alignments found/generated. dir is: $dir");
ok(-d $dir, "result is a real directory");
ok(-s $dir."/all_sequences.bam", "found a bam file in there");


###########################################Test 2: Create a new Maq alignment################################# 

$ins_data_params{id} = '-123458';
$ins_data_params{median_insert_size} = 313; 
my $instrument_data2 = Genome::InstrumentData::Solexa->create_mock(%ins_data_params);

isa_ok($instrument_data2,'Genome::InstrumentData::Solexa');
$instrument_data2->set_always('sample_type','dna');
$instrument_data2->set_always('resolve_quality_converter','sol2sanger');
$instrument_data2->set_always('run_start_date_formatted','Fri Jul 10 00:00:00 CDT 2009');
$instrument_data2->set_always('sample_id','2791246676');
$instrument_data2->set_always('is_paired_end',1);
ok($instrument_data2->is_paired_end,'instrument data is paired end');

my $tmp_dir = File::Temp::tempdir('Align-Maq-XXXXX', DIR => Genome::Utility::FileSystem->base_temp_directory, CLEANUP => 1);
my $staging_base = sprintf("alignment-%s-%s-%s", hostname(), $ENV{USER}, $$);

my $tmp_allocation = Genome::Disk::Allocation->__define__(
    id                  => '-123459',
    disk_group_name     => 'info_alignments',
    group_subdirectory  => 'test',
    mount_path          => $tmp_dir,
    allocation_path     => 'alignment_data/maq0_7_1/refseq-for-test/test_run_name/4_-123458/' . $staging_base,
    allocator_id        => '-123459',
    kilobytes_requested => 100000,
    kilobytes_used      => 0,
    owner_id            => $instrument_data->id,
    owner_class_name    => 'Genome::InstrumentData::Solexa',
);
mkpath($tmp_allocation->absolute_path);

# manage reallocation since we are not actually doing a real allocation
*Genome::Disk::Allocation::reallocate = sub { print "I would reallocate here!!\n"};

isa_ok($tmp_allocation,'Genome::Disk::Allocation');

@fastq_files = glob($instrument_data2->gerald_directory.'/*.txt');

$instrument_data2->set_list('dump_sanger_fastq_files', @fastq_files);
$instrument_data2->set_always('calculate_alignment_estimated_kb_usage',10000);
$instrument_data2->set_always('resolve_quality_converter','sol2sanger');

$align_param{instrument_data_id} = $instrument_data2->id;
$alignment = Genome::InstrumentData::AlignmentResult::Maq->create(%align_param);

# once to make new data
ok($alignment, "Created Maq Alignment");
$dir = $alignment->alignment_directory;
ok($dir, "alignments found/generated");
ok(-d $dir, "result is a real directory");
ok(-s $dir . "/all_sequences.bam", "result has a bam file");

# clear out the fastqs so we re-unpack them again

my $base_tempdir = Genome::Utility::FileSystem->base_temp_directory;
note "Remove all content under $base_tempdir\n";
my @base_temp_files = glob($base_tempdir . "/*");
for (@base_temp_files) {
    print "$_\n";
    File::Path::rmtree($_);
}


##########################################Test 3:fragment###################################

# Run paired end as fragment

$tmp_allocation->allocation_path('alignment_data/maq0_7_1/refseq-for-test/test_run_name/fragment/4_-123458/' . $staging_base);
mkpath($tmp_allocation->absolute_path);
$instrument_data2->set_list('dump_sanger_fastq_files', $fastq_files[0]);

$align_param{instrument_data_id} = $instrument_data2->id;
$align_param{force_fragment} = 1;
$alignment = Genome::InstrumentData::AlignmentResult::Maq->create(%align_param);

ok($alignment, "Created Alignment");
$dir = $alignment->alignment_directory;
ok($dir, "alignments found/generated");
ok(-d $dir, "result is a real directory");
ok(-s $dir . "/all_sequences.bam", "result has a bam file");

