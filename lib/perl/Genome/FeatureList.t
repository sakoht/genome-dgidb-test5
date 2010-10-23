#!/gsc/bin/perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1; #FeatureLists generate their own IDs, but this is still a good idea
};

use Test::More tests => 23;

use above 'Genome';

use_ok('Genome::FeatureList');

my $test_bed_file = __FILE__ . '.d/1.bed';
my $test_merged_bed_file = __FILE__ . '.d/1.merged.bed';
ok(-e $test_bed_file, 'test file ' . $test_bed_file . ' exists');
ok(-e $test_merged_bed_file, 'test file ' . $test_merged_bed_file . ' exists');

my $test_bed_file_md5 = Genome::Utility::FileSystem->md5sum($test_bed_file);

my $feature_list = Genome::FeatureList->create(
    name                => 'GFL test feature-list',
    format              => 'true-BED',
    content_type        => 'target region set',
    file_path           => $test_bed_file,
    file_content_hash   => $test_bed_file_md5,
);

ok($feature_list, 'created a feature list');
isa_ok($feature_list, 'Genome::FeatureList');
ok($feature_list->verify_file_md5, 'bed file md5 checks out');
is($feature_list->file_content_hash, $feature_list->verify_file_md5, 'verify_bed_file_md5 calculated the expected value');

my $file_path = $feature_list->file_path;
my $diff = Genome::Utility::FileSystem->diff_file_vs_file($test_bed_file, $file_path);
ok(!$diff, 'returned file matches expected file')
    or diag("diff:\n" . $diff);

my $merged_file = $feature_list->merged_bed_file;
ok(-s $merged_file, 'merged file created');
my $merged_diff = Genome::Utility::FileSystem->diff_file_vs_file($merged_file, $test_merged_bed_file);
ok(!$merged_diff, 'returned file matches expected file')
    or diag("diff:\n" . $merged_diff);

my $test_id = Genome::FeatureList->_next_id;
ok($test_id, 'generated a new possible ID');
ok(!scalar ($test_id =~ /\s/), 'possible ID has no spaces');

my $feature_list_with_bad_md5 = Genome::FeatureList->create(
    name                => 'GFL bad MD5 list',
    format              => 'true-BED',
    content_type        => 'target region set',
    file_path           => $test_bed_file,
    file_content_hash   => 'abcdef0123456789abcdef0123456789',
);
ok(!$feature_list_with_bad_md5, 'failed to produce a new object when MD5 was incorrect');


#90528 is 'agilent sureselect MOUSE exome v1'
my $lims_feature_list = Genome::FeatureList->create(
    name                => 'agilent sureselect MOUSE exome v1 -- test',
    format              => '1-based',
    content_type        => 'target region set',
    file_id             => '90528',
    file_content_hash   => 'f6e55d07aee3c6673151c0b22286e198',
);
ok($lims_feature_list, 'created a feature list based on a LIMS file');
my $dumped_file_path = $lims_feature_list->file_path;
ok(-s $dumped_file_path, 'LIMS BED file dumped to file-system');
is(Genome::Utility::FileSystem->md5sum($dumped_file_path), $lims_feature_list->file_content_hash, 'Dumped MD5 matches stored value');

my $test_multitracked_1based_bed = __FILE__ . '.d/2.bed';
my $test_multitracked_1based_merged_bed = __FILE__ . '.d/2.merged.bed';
ok(-e $test_multitracked_1based_bed, 'test file ' . $test_multitracked_1based_bed . ' exists');
ok(-e $test_multitracked_1based_merged_bed, 'test file ' . $test_multitracked_1based_merged_bed . ' exists');

my $test_multitracked_1based_bed_md5 = Genome::Utility::FileSystem->md5sum($test_multitracked_1based_bed);

my $feature_list_2 = Genome::FeatureList->create(
    name                => 'GFL test multi-tracked 1-based feature-list',
    format              => 'multi-tracked 1-based',
    content_type        => 'target region set',
    file_path           => $test_multitracked_1based_bed,
    file_content_hash   => $test_multitracked_1based_bed_md5,
);
ok($feature_list_2, 'created multi-tracked 1-based feature list');
ok($feature_list_2->verify_file_md5, 'bed file md5 checks out');
is($test_multitracked_1based_bed_md5, $feature_list_2->verify_file_md5, 'verify_bed_file_md5 calculated the expected value');

my $merged_file_2 = $feature_list_2->merged_bed_file;
ok(-s $merged_file_2, 'merged file created');
my $merged_diff_2 = Genome::Utility::FileSystem->diff_file_vs_file($merged_file_2, $test_multitracked_1based_merged_bed);
ok(!$merged_diff_2, 'returned file matches expected file')
    or diag("diff:\n" . $merged_diff_2);
