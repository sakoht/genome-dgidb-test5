#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use Test::More tests => 8;

use above 'Genome';

use_ok('Genome::Model::Tools::DetectVariants2::Classify::Loh') or die('cannot run tests without module');

my ($somatic_snv_result, $control_snv_result) = &setup_prior_results();
isa_ok($somatic_snv_result, 'Genome::Model::Tools::DetectVariants2::Result::Base', 'generated somatic prior result');
isa_ok($control_snv_result, 'Genome::Model::Tools::DetectVariants2::Result::Base', 'generated control prior result');

my ($somatic_expected_file, $loh_expected_file) = &expected_output_files();
ok(-e $somatic_expected_file, 'somatic expected file exists');
ok(-e $loh_expected_file, 'loh expected file exists');

my $loh_result = Genome::Model::Tools::DetectVariants2::Classify::Loh->create(
    prior_result_id => $somatic_snv_result->id,
    control_result_id => $control_snv_result->id,
    classifier_version => 1,
);
isa_ok($loh_result, 'Genome::Model::Tools::DetectVariants2::Classify::Loh', 'created LOH result');

my $output_dir = $loh_result->output_dir;
my $version = 2;
my $somatic_output = $output_dir."/snvs.somatic.v".$version.".bed";
my $loh_output = $output_dir."/snvs.loh.v".$version.".bed";

ok(!Genome::Sys->diff_file_vs_file($somatic_expected_file, $somatic_output), 'somatic file is as expected')
    or diag("diff:\n" . Genome::Sys->diff_file_vs_file($somatic_expected_file, $somatic_output));
ok(!Genome::Sys->diff_file_vs_file($loh_expected_file, $loh_output), 'loh file is as expected')
    or diag("diff:\n" . Genome::Sys->diff_file_vs_file($loh_expected_file, $loh_output));





sub setup_prior_results {

    my $somatic_output_dir = Genome::Sys->create_temp_directory();
    my $somatic_snv_result = Genome::Model::Tools::DetectVariants2::Result->__define__(
        detector_name => 'Genome::Model::Tools::DetectVariants2::Result::Samtools',
        detector_version => 'r599',
        output_dir => $somatic_output_dir,
    );
    my $somatic_snv_file = join('/', $somatic_output_dir, 'snvs.hq');
    Genome::Sys->write_file($somatic_snv_file, <<EOFILE
1	2612085	T	G	99	22	49	51	35	244	127
1	3496118	T	C	99	70	97	150	59	56	43
1	11276955	T	C	99	31	58	111	60	31	22
1	14106900	C	T	99	19	46	171	60	56	38
1	15997730	G	A	99	26	53	138	40	47	27
1	16683503	C	T	99	47	80	105	58	28	21
1	17196565	T	C	99	38	65	117	60	32	28
1	17196589	A	G	99	32	59	96	60	36	27
1	19204182	G	A	99	34	61	88	60	33	33
1	20086913	A	G	99	27	54	141	60	42	19
2	6069	T	W	99	33	8	9	15	111	112
2	526787	G	A	99	27	14	20	18	67	41
2	555850	C	T	99	39	20	156	45	61	30
2	559113	G	A	99	27	8	8	21	57	12
2	591004	C	T	99	17	17	17	19	51	19
2	714816	A	W	99	44	17	17	50	52	51
2	812823	C	Y	99	67	79	79	58	95	96
2	815735	G	A	99	35	8	8	59	205	159
2	849548	G	A	99	29	48	48	60	7	2
2	853466	T	C	99	55	35	35	44	28	27
EOFILE
    );
    Genome::Model::Tools::Bed::Convert::Snv::SamtoolsToBed->execute(
        source => $somatic_snv_file,
        output => $somatic_snv_file .'.bed',
    );

    my $control_output_dir = Genome::Sys->create_temp_directory();
    my $control_snv_result = Genome::Model::Tools::DetectVariants2::Result->__define__(
        detector_name => 'Genome::Model::Tools::DetectVariants2::Result::Samtools',
        detector_version => 'r599',
        output_dir => $control_output_dir,
    );
    my $control_snv_file = join('/', $control_output_dir, 'snvs.hq');
    Genome::Sys->write_file($control_snv_file, <<EOFILE
1	2612085	T	G	99	22	49	51	35	244	127
1	3496118	T	C	99	70	97	150	59	56	43
1	11276955	T	C	99	31	58	111	60	31	22
1	14106900	C	T	99	19	46	171	60	56	38
1	15997730	G	A	99	26	53	138	40	47	27
1	16683503	C	K	99	47	80	105	58	28	21
1	17196565	T	M	99	38	65	117	60	32	28
1	17196589	A	K	99	32	59	96	60	36	27
1	19204182	G	M	99	34	61	88	60	33	33
1	20086913	A	G	99	27	54	141	60	42	19
2	6069	T	A	99	33	8	9	15	111	112
2	526787	G	A	99	27	14	20	18	67	41
2	555850	C	Y	99	39	20	156	45	61	30
2	559113	G	R	99	27	8	8	21	57	12
2	591004	C	Y	99	17	17	17	19	51	19
2	714816	A	W	99	44	17	17	50	52	51
2	812823	C	Y	99	67	79	79	58	95	96
2	815735	G	R	99	35	8	8	59	205	159
2	849548	G	A	99	29	48	48	60	7	2
2	853466	T	W	99	55	35	35	44	28	27
EOFILE
    );
    Genome::Model::Tools::Bed::Convert::Snv::SamtoolsToBed->execute(
        source => $control_snv_file,
        output => $control_snv_file .'.bed',
    );
    return ($somatic_snv_result, $control_snv_result);
}

sub expected_output_files {
    my $somatic_output_file = Genome::Sys->create_temp_file_path;
    Genome::Sys->write_file($somatic_output_file, <<EOFILE
1	2612084	2612085	T/G	99	51
1	3496117	3496118	T/C	99	150
1	11276954	11276955	T/C	99	111
1	14106899	14106900	C/T	99	171
1	15997729	15997730	G/A	99	138
1	20086912	20086913	A/G	99	141
2	6068	6069	T/W	99	9
2	526786	526787	G/A	99	20
2	714815	714816	A/W	99	17
2	812822	812823	C/Y	99	79
2	849547	849548	G/A	99	48
2	853465	853466	T/C	99	35
EOFILE
    );

    my $loh_output_file = Genome::Sys->create_temp_file_path;
    Genome::Sys->write_file($loh_output_file, <<EOFILE
1	16683502	16683503	C/T	99	105
1	17196564	17196565	T/C	99	117
1	17196588	17196589	A/G	99	96
1	19204181	19204182	G/A	99	88
2	555849	555850	C/T	99	156
2	559112	559113	G/A	99	8
2	591003	591004	C/T	99	17
2	815734	815735	G/A	99	8
EOFILE
    );

    return ($somatic_output_file, $loh_output_file);
}
