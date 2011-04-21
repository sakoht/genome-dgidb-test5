#! /gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

use Data::Dumper 'Dumper';
use Genome::Model::MetagenomicComposition16s::Test;
use Test::More;

$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
$ENV{UR_DBI_NO_COMMIT} = 1;

use_ok('Genome::Model::Build::MetagenomicComposition16s::Solexa') or die;

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
my $inst_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model/MetagenomicComposition16sSolexa/inst_data';
ok(-d $inst_data_dir, 'inst data dir') or die;

my $instrument_data = Genome::InstrumentData::Solexa->create(
    id => -7777,
    library => $library,
    flow_cell_id => '12345',
    lane => '1',
    median_insert_size => '22',
    run_name => '110101_TEST',
    subset_name => 4,
    run_type => 'Paired',
#   gerald_directory => '/gsc/var/cache/testsuite/data/Genome-InstrumentData-Align-Maq/test_sample_name', #needed?
    bam_path => '/gsc/var/cache/testsuite/data/Genome-InstrumentData-AlignmentResult-Bwa/input.bam',
);
ok($instrument_data, 'create inst data');

# temp test dir
my $tmpdir = Genome::Sys->create_temp_directory;

my @fastq_files = $instrument_data->dump_fastqs_from_bam( directory => $tmpdir );
ok ( @fastq_files, "Dumped fastqs from bam file" );
#TODO - compare fastq files??

# pp
my $pp = Genome::ProcessingProfile->get(2591278); # exists and cannot recreate w/ same params
ok($pp, 'got solexa pp') or die;

# model
my $model = Genome::Model::MetagenomicComposition16s->create(
    processing_profile => $pp,
    subject_name => $sample->name,
    subject_type => 'sample_name',
    data_directory => $tmpdir,
);
ok($model, 'MC16s solexa model') or die;
ok($model->add_instrument_data($instrument_data), 'add inst data to model');

# create w/o subclass
my $build = Genome::Model::Build::MetagenomicComposition16s->create(
    model => $model,
    data_directory => $model->data_directory.'/build',
);
isa_ok($build, 'Genome::Model::Build::MetagenomicComposition16s::Solexa');

# metrics
is($build->amplicons_attempted(20), 20, 'amplicons attempted');
is($build->amplicons_processed(15), 15, 'amplicons processed');
is(
    $build->amplicons_processed_success( 
        $build->amplicons_processed / $build->amplicons_attempted
    ), .75, 'amplicons processed success'
);

# calculated kb
is($build->calculate_estimated_kb_usage, 500_000, 'estimated kb usage'); 

# dirs
my $existing_build_dir = '/gsc/var/cache/testsuite/data/Genome-Model/MetagenomicComposition16sSolexa/build_kk'; #just overwrite /build .. check w/ eddie
ok(-d $existing_build_dir, 'existing build dir exists');

my $classification_dir = $build->classification_dir;
is($classification_dir, $build->data_directory.'/classification', 'classification_dir');
ok(-d $classification_dir, 'classification_dir exists');

my $amplicon_classifications_dir = $build->amplicon_classifications_dir;
is($amplicon_classifications_dir, $build->data_directory.'/sys', 'amplicon_classifications_dir');
ok(-d $amplicon_classifications_dir, 'amplicon_classifications_dir exists');

my $fasta_dir = $build->fasta_dir;
is($fasta_dir, $build->data_directory.'/fasta', 'fasta_dir');
ok(-d $fasta_dir, 'fasta_dir exists');

ok(_link_dir_contents($existing_build_dir.'/fasta', $fasta_dir), "linked fasta_dir") or die;

# files
my $file_base = $build->file_base_name;
is($file_base, $build->subject_name, 'file base');
#print $file_base.' '.$build->subject_name."\n";

#<STDIN>;
done_testing(); exit;

#< CLASSIFY >#
ok($build->classify_amplicons, 'classify amplicons');
is($build->amplicons_classified, '15', 'amplicons classified');
is($build->amplicons_classified_success, '1.00', 'amplicons classified success');
is($build->amplicons_classification_error, 0, 'amplicons classified error');

#< ORIENT >#
ok($build->orient_amplicons, 'orient amplicons');

my @standards = (
    { name => 'V1_V3', amplicons => [qw/ FZ0V7MM01A01AQ FZ0V7MM01A01O4 FZ0V7MM01A02JE FZ0V7MM01A02T9 FZ0V7MM01A0327 /] },
    { name => 'V3_V5', amplicons => [qw/ FZ0V7MM01A00L3 FZ0V7MM01A00YG FZ0V7MM01A02O2 FZ0V7MM01A03HG FZ0V7MM01A03PV /] },
    { name => 'V6_V9', amplicons => [qw/ FZ0V7MM01A004O FZ0V7MM01A00FU FZ0V7MM01A00G0 FZ0V7MM01A00IA FZ0V7MM01A00XH /] },
);

#< Amplicon Set Names >#
my @set_names = $build->amplicon_set_names;
is_deeply(\@set_names, [ sort map { $_->{name} } @standards ], 'amplicon set names');
my @amplicon_sets = $build->amplicon_sets;
is(scalar(@amplicon_sets), 3, 'got 3 amplicon sets');
my $cnt = 0;
for my $amplicon_set ( @amplicon_sets ) {
    # name
    my $set_name = $amplicon_set->name;
    is($set_name, $standards[$cnt]->{name}, 'amplicon set name');
    # fastas
    for my $type (qw/ processed oriented /) {
        my $method = $type.'_fasta_file_for_set_name';
        my $fasta_file = $build->$method($set_name);
        is(
            $fasta_file,
            $fasta_dir.'/'.$file_base.'.'.$set_name.'.'.$type.'.fasta',
            "$type fasta file for set name: $set_name"
        );
        ok(-s $fasta_file, "$type fasta file name exists for set $set_name")
    }
    # classification
    my $classification_file = $build->classification_file_for_set_name($set_name);
    is(
        $classification_file,
        $classification_dir.'/'.$file_base.'.'.$set_name.'.'.$build->classifier,
        "classification file name for set name: $set_name"
    );
    # amplicons
    my @amplicon_names;
    while ( my $amplicon = $amplicon_set->next_amplicon ) {
        my $classification_file = $build->classification_file_for_amplicon_name($amplicon->name);
        is(
            $classification_file,
            $amplicon_classifications_dir.'/'.$amplicon->name.'.classification.stor',
            "classification file for amplicon name: ".$amplicon->name,
        );
        push @amplicon_names, $amplicon->name;
    }
    is_deeply(\@amplicon_names, $standards[$cnt]->{amplicons}, "amplicons match for $set_name");
    $cnt++;
}

#print $build->data_directory."\n";<STDIN>;
done_testing();

exit;

#######################################################################################

sub _link_dir_contents {
    my ($source_dir, $dest_dir) = @_;

    Genome::Sys->validate_existing_directory($dest_dir)
        or die;

    my $dh = Genome::Sys->open_directory($source_dir)
        or die;

    $dh->read; $dh->read; # . and .. dirs
    while ( my $file = $dh->read ) {
        my $target = "$source_dir/$file";
        my $link =  $dest_dir.'/'.$file;
        unless ( symlink($target, $link) ) {
            die "Can't symlink ($target) to ($link): $!.";
        }
    }

    return 1;
}

