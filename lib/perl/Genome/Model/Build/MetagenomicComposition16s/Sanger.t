#! /gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

use Data::Dumper 'Dumper';
require File::Compare;
use Test::More;

$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
$ENV{UR_DBI_NO_COMMIT} = 1;

# use
use_ok('Genome::Model::Build::MetagenomicComposition16s::Sanger') or die;

# taxon, sample, lib
my $taxon = Genome::Taxon->create(
    name => 'Human Metagenome TEST',
    domain => 'Unknown',
    current_default_org_prefix => undef,
    estimated_genome_size => undef,
    current_genome_refseq_id => undef,
    ncbi_taxon_id => undef,
    ncbi_taxon_species_name => undef,
    species_latin_name => 'Human Metagenome',
    strain_name => 'TEST',
);
ok($taxon, 'create taxon');

my $sample = Genome::Sample->create(
    id => -1234,
    #name => 'HUMET-TEST-000',
    name => 'H_GV-933124G-S.MOCK',
    taxon_id => $taxon->id,
);
ok($sample, 'create sample');

my $library = Genome::Library->create(
    id => -12345,
    name => $sample->name.'-testlibs',
    sample_id => $sample->id,
);
ok($library, 'create library');

# inst data
my $inst_data_id = '01jan00.101amaa';
my $inst_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model/MetagenomicComposition16sSanger/inst_data/'.$inst_data_id;
ok(-d $inst_data_dir, 'inst data dir') or die;
my $instrument_data = Genome::InstrumentData::Sanger->create(
    id => $inst_data_id,
    library => $library,
);
ok($instrument_data, 'create inst data') or die;
no warnings qw/ once redefine /;
*Genome::InstrumentData::Sanger::dump_to_file_system = sub{ return 1; };
*Genome::InstrumentData::Sanger::full_path = sub{ return $inst_data_dir; };
use warnings;
ok(-d $instrument_data->full_path, 'full path');

# pp
my $pp = Genome::ProcessingProfile->create(
    type_name => 'metagenomic composition 16s',
    name => 'MC16s Sanger TEST',
    sequencing_platform => 'sanger',
    amplicon_size => 1150,
    sequencing_center => 'gsc',
    assembler => 'phred_phrap',
    assembler_params => '-vector_bound 0 -trim_qual 0',
    classifier => 'rdp2-1',
    classifier_params => '-training_set broad',
);
ok($pp, 'create sanger pp') or die;

# dirs
my $tmpdir = File::Temp::tempdir(CLEANUP => 1);

# model
my $model = Genome::Model::MetagenomicComposition16s->create(
    processing_profile => $pp,
    processing_profile => $pp,
    subject_name => $sample->name,
    subject_type => 'sample_name',
    data_directory => $tmpdir,
);
ok($model, 'MC16s sanger model') or die;
ok($model->add_instrument_data($instrument_data), 'add inst data to model');

my $example_build = $model->create_build(
    model=> $model,
    id => -2288,
    data_directory => '/gsc/var/cache/testsuite/data/Genome-Model/MetagenomicComposition16sSanger/build',
);
ok($example_build, 'example build') or die;

my $build = Genome::Model::Build::MetagenomicComposition16s->create(
    id => -1199,
    model => $model,
    data_directory => $model->data_directory.'/build',
);
isa_ok($build, 'Genome::Model::Build::MetagenomicComposition16s::Sanger');

# description
is(
    $build->description, 
    #qr/metagenomic composition 16s sanger build (-\d) for model (mr. mock -\d)/,
    sprintf( 'metagenomic composition 16s sanger build (%s) for model (%s %s)',
        $build->id, $build->model->name, $build->model->id,
    ),
    'description',
);

# calculated kb
is($build->calculate_estimated_kb_usage, 30000, 'Estimated kb usage');

# dirs
my $existing_build_dir = '/gsc/var/cache/testsuite/data/Genome-Model/MetagenomicComposition16sSanger/build';
ok(-d $existing_build_dir, 'existing build dir exists');
for my $subdir ( $build->sub_dirs ) {
    my $method = $subdir;
    $method .= '_dir' if $subdir !~ /_dir$/;
    my $dir = $build->$method;
    is($dir, $build->data_directory.'/'.$subdir, "$method is correct");
    ok(-d $dir, "$method was created");
}

# file base
my $file_base_name = $build->file_base_name;
is($file_base_name, 'H_GV-933124G-S.MOCK', 'build file base name');

# fastas
my $fasta_base = $build->fasta_dir."/$file_base_name";
my %file_methods_and_results = (
    processed_fasta_file => $fasta_base.'.processed.fasta',
    processed_qual_file => $fasta_base.'.processed.fasta.qual',
    oriented_fasta_file => $fasta_base.'.oriented.fasta',
    oriented_qual_file => $fasta_base.'.oriented.fasta.qual',
);
for my $file_name ( keys %file_methods_and_results ) {
    my $method = $file_name.'_for_set_name';
    is($build->$method(''), $file_methods_and_results{$file_name}, $file_name);
}

#< PREPARE >#
ok($build->prepare_instrument_data, 'prepare instrument data');
my @amplicon_sets = $build->amplicon_sets;
is(@amplicon_sets, 1, 'amplicon sets');
my $amplicon_set = $amplicon_sets[0];
my ($example_amplicon_set) = $example_build->amplicon_sets;

ok(-s $amplicon_set->processed_fasta_file, 'processed fasta file');
is(
    File::Compare::compare($amplicon_set->processed_fasta_file, $example_amplicon_set->processed_fasta_file), 
    0,
    'processed amplicon fasta file matches',
);
ok(-s $amplicon_set->processed_qual_file, 'processed qual file');
is(
    File::Compare::compare($amplicon_set->processed_qual_file, $example_amplicon_set->processed_qual_file), 
    0,
    'processed amplicon qual file matches',
);
my @amplicon_names;
while ( my $amplicon = $amplicon_set->next_amplicon ) {
    ok(-s $build->reads_fasta_file_for_amplicon($amplicon), 'fasta file');
    ok(-s $build->reads_qual_file_for_amplicon($amplicon), 'qual file');
    ok(-s $build->ace_file_for_amplicon($amplicon), 'ace file');
    push @amplicon_names, $amplicon->{name};
}
is_deeply(
    \@amplicon_names,
    [qw/ HMPB-aad13a05 HMPB-aad13e12 HMPB-aad15e03 HMPB-aad16a01 HMPB-aad16c10 /],
    'Got 5 amplicons',
);

ok(-s $build->raw_reads_fasta_file, 'Created the raw reads fasta file');
# Time diffs prevent comparing files. Maybe update the desc for these reads
#is(File::Compare::compare($build->raw_reads_fasta_file, $example_build->raw_reads_fasta_file), 0, 'raw reads fasta file matches');
ok(-s $build->raw_reads_qual_file, 'Created the raw reads qual file');

ok(-s $build->processed_reads_fasta_file, 'Created the processed reads fasta file');
# Time diffs prevent comparing files. Maybe update the desc for these reads
#is(File::Compare::compare($build->processed_reads_fasta_file, $example_build->processed_reads_fasta_file), 0, 'processed reads fasta file matches');
ok(-s $build->processed_reads_qual_file, 'Created the processed reads qual file');

# metrics
is($build->amplicons_attempted, 5, 'amplicons attempted is 5');
is($build->amplicons_processed, 4, 'amplicons processed is 4');
is($build->amplicons_processed_success, '0.80', 'amplicons processed success is 0.80');
is($build->reads_attempted, 30, 'reads attempted is 30');
is($build->reads_processed, 17, 'reads processed is 17');
is($build->reads_processed_success, '0.57', 'reads processed success is 0.57');

#< CLASSIFY >#
my $classification_file = $build->classification_file_for_set_name( $amplicon_set->name );
my $classification_dir = $build->classification_dir;
is(
    $classification_file, 
    $classification_dir.'/'.$file_base_name.'.'.$build->classifier,
    'classification file name for set name \''.$amplicon_set->name.'\' is correct');
is(
    $classification_file, 
    $amplicon_set->classification_file,
    'classification file name from build and amplicon set match',
);
ok($build->classify_amplicons, 'classify amplicons');
ok(-s $classification_file, 'created classification file');
@amplicon_sets = $build->amplicon_sets;
is(@amplicon_sets, 1, 'Got one amplicon set');
$amplicon_set = $amplicon_sets[0];
my $classified_cnt = 0;
while ( my $amplicon = $amplicon_set->next_amplicon ) {
    next if not $amplicon->{seq}; # did not assemble, no classification
    $classified_cnt++;
    ok($amplicon->{classification}, $amplicon->{name}.' has a classification');
    is($amplicon->{classification}->[0], $amplicon->{name}, 'classification name matches');
    is($amplicon->{classification}->[1], '-', 'is not complemented');
}
is($build->amplicons_classified, $classified_cnt, 'amplicons classified correct');
is($build->amplicons_classified_success, '1.00', 'amplicons classified success');
is($build->amplicons_classification_error, 0, 'amplicons classified error');

#< ORIENT ># rm files, orient, check
ok($build->orient_amplicons, 'orient amplicons');
ok(-s $build->oriented_fasta_file, 'created oriented fasta file');
ok(-s $build->oriented_qual_file, 'created oriented qual file');

# Setup for contamination and latest iteration
my %mock_reads = _create_mock_gsc_sequence_reads() or die;
no warnings 'redefine';
no warnings 'once';
local *GSC::Sequence::Read::get = sub{ 
    die "No mock read for ".$_[2] unless exists $mock_reads{$_[2]};
    return $mock_reads{$_[2]};
};
use warnings;

# contamination - should get 4 amplicons
$build->processing_profile->exclude_contaminated_amplicons(1);
@amplicon_sets = $build->amplicon_sets;
$amplicon_set = $amplicon_sets[0];
my @uncontaminated_amplicons;
while ( my $amplicon = $amplicon_set->next_amplicon ) {
    push @uncontaminated_amplicons, $amplicon;
}
is_deeply(
    [ map { $_->{name} } @uncontaminated_amplicons ],
    [qw/ HMPB-aad13a05 HMPB-aad13e12 HMPB-aad16a01 HMPB-aad16c10 /],
    'Got 4 uncontaminated amplicons using all read iterations',
);

# latest iteration of reads - 5 amplicons because the contaminated read is older
$build->processing_profile->only_use_latest_iteration_of_reads(1);
my @only_latest_reads_amplicons;
@amplicon_sets = $build->amplicon_sets;
$amplicon_set = $amplicon_sets[0];
while ( my $amplicon = $amplicon_set->next_amplicon ) {
    push @only_latest_reads_amplicons, $amplicon;
}
is_deeply(
    [ map { $_->{name} } @only_latest_reads_amplicons ],
    [qw/ HMPB-aad13a05 HMPB-aad13e12 HMPB-aad15e03 HMPB-aad16a01 HMPB-aad16c10 /],
    'Got 5 uncontaminated amplicons using only latest read iterations',
);
is_deeply(
    $only_latest_reads_amplicons[0]->{reads},
    [qw/ 
    HMPB-aad13a05.b3
    HMPB-aad13a05.b4
    HMPB-aad13a05.g1
    /],
    'Got latest iterations for reads'
);

#print $build->data_directory."\n";<STDIN>;
done_testing();
exit;

#####################################################################################

sub _create_mock_gsc_sequence_reads {
    my %reads;
    my %read_params = (
        'HMPB-aad13a05.b1' => {
            'run_date' => '16-MAY-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad13a05.b2' => {
            'run_date' => '17-MAY-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad13a05.b3' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad13a05.b4' => {
            'run_date' => '02-OCT-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad13a05.g1' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-28RPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad13a05.g2' => {
            'run_date' => '20-MAY-2008',
            'primer_code' => '-28RPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad13e12.b1' => {
            'run_date' => '16-MAY-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad13e12.b2' => {
            'run_date' => '17-MAY-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad13e12.b3' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad13e12.b4' => {
            'run_date' => '02-OCT-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad13e12.g1' => {
            'run_date' => '20-MAY-2008',
            'primer_code' => '-28RPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad13e12.g2' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-28RPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad15e03.b1' => {
            'run_date' => '16-MAY-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad15e03.b2' => {
            'run_date' => '17-MAY-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad15e03.b3' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad15e03.b4' => {
            'run_date' => '02-OCT-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad15e03.g1' => {
            'run_date' => '20-MAY-2008',
            'primer_code' => '-28RPpOT',
            # CONTAMINATED READ #
            'is_contaminated' => 1,
        },
        'HMPB-aad15e03.g2' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-28RPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad16a01.b1' => {
            'run_date' => '16-MAY-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad16a01.b2' => {
            'run_date' => '17-MAY-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad16a01.b3' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad16a01.b4' => {
            'run_date' => '02-OCT-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad16a01.g1' => {
            'run_date' => '20-MAY-2008',
            'primer_code' => '-28RPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad16a01.g2' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-28RPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad16c10.b1' => {
            'run_date' => '16-MAY-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad16c10.b2' => {
            'run_date' => '17-MAY-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad16c10.b3' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-21UPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad16c10.b4' => {
            'run_date' => '02-OCT-2008',
            'primer_code' => '907R',
            'is_contaminated' => 0,
        },
        'HMPB-aad16c10.g1' => {
            'run_date' => '20-MAY-2008',
            'primer_code' => '-28RPpOT',
            'is_contaminated' => 0,
        },
        'HMPB-aad16c10.g2' => {
            'run_date' => '01-OCT-2008',
            'primer_code' => '-28RPpOT',
            'is_contaminated' => 0,
        },
    );
    for my $read_name ( keys %read_params ) {
        $reads{$read_name} = Test::MockObject->new();
        $reads{$read_name}->set_always('trace_name', $read_name);
        my $screen_reads_stat_hmp = Test::MockObject->new();
        $screen_reads_stat_hmp->set_always(
            'is_contaminated',
            $read_params{$read_name}->{is_contaminated}
        );
        $reads{$read_name}->set_always('get_screen_read_stat_hmp', $screen_reads_stat_hmp);
        for my $attr ( keys %{$read_params{$read_name}} ) {
            $reads{$read_name}->set_always($attr, $read_params{$read_name}->{$attr});
        }
    }

    return %reads;
}

