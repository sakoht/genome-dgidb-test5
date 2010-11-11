#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use above "Genome";
use Test::More tests => 16;
use Data::Dumper;
use_ok('Genome::Model::Build::ImportedAnnotation');

# create a test annotation build and a few reference sequence builds to test compatibility with
my @species_names = ('human', 'mouse');
my @versions = ('12_34', '56_78');
my $pp_ref = Genome::ProcessingProfile::ImportedReferenceSequence->create(name => 'test_pp_ref');
my $pp_ann = Genome::ProcessingProfile::ImportedAnnotation->get_or_create(name => 'test_pp_ann', annotation_source => 'test_source');
my $data_dir = File::Temp::tempdir('ImportedAnnotationTest-XXXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);

my %samples;
for my $sn (@species_names) {
    my $p = Genome::Individual->create(name => "test-$sn-patient", common_name => 'testpatient');
    my $s = Genome::Sample->create(name => "test-$sn-patient", species_name => $sn, common_name => 'tumor', source => $p);
    ok($s, 'created sample');
    $samples{$sn} = $s;
}

my $ann_model = Genome::Model::ImportedAnnotation->create(
    name                => "test_annotation",
    processing_profile  => $pp_ann,
    subject_class_name  => ref($samples{'human'}),
    subject_id          => $samples{'human'}->id,
);
ok($ann_model, "created annotation model");

my $abuild = Genome::Model::Build::ImportedAnnotation->create(
    model           => $ann_model,
    data_directory  => $data_dir,
    version         => $versions[0],
);
ok($abuild, "created annotation build");

my %rbuilds;
for my $sn (@species_names) {
    $rbuilds{$sn} = [];

    my $ref_model = Genome::Model::ImportedReferenceSequence->create(
        name                => "test_ref_sequence_$sn",
        processing_profile  => $pp_ref,
        subject_class_name  => ref($samples{$sn}),
        subject_id          => $samples{$sn}->id,
    );
    ok($ref_model, "created reference sequence model ($sn)");

    for my $v (@versions) {
        $v =~ /.*_([0-9]+)/;
        my $short_version = $1;
        my $rs = Genome::Model::Build::ImportedReferenceSequence->create(
            name            => "ref_sequence_${sn}_$short_version",
            model           => $ref_model,
            fasta_file      => 'nofile', 
            data_directory  => $data_dir,
            version         => $short_version,
            );
        ok($rs, "created ref seq build $sn $v");
        push(@{$rbuilds{$sn}}, $rs);
    }
}

is($abuild->idstring, "test_annotation/$versions[0]", "idstring properly formed");
ok($abuild->is_compatible_with_reference_sequence_build($rbuilds{'human'}->[0]), 'reference sequence compatibility');
ok(!$abuild->is_compatible_with_reference_sequence_build($rbuilds{'human'}->[1]), 'reference sequence incompatibility');
ok(!$abuild->is_compatible_with_reference_sequence_build($rbuilds{'mouse'}->[0]), 'reference sequence incompatibility');
ok(!$abuild->is_compatible_with_reference_sequence_build($rbuilds{'mouse'}->[1]), 'reference sequence incompatibility');

done_testing();
