#!/gsc/bin/perl


###################################
# Add Reads Solexa/Maq test suite #
###################################

use strict;
use warnings;

use Data::Dumper;
use File::Temp;
use File::Path;
use Test::More;

use above "Genome";
use Genome::Model::Command::Build::ReferenceAlignment::Test;

use GSCApp;
App::DB->db_access_level('rw');
App::DB::TableRow->use_dummy_autogenerated_ids(1);
App::DBI->no_commit(1);
App->init;

$ENV{UR_DBI_NO_COMMIT} = 1;

# NOTE: run from 32-bit first to compile correct inline libraries
# Then this should run from 64-bit to actually execute.
my $archos = `uname -a`;
if ($archos !~ /64/) {
    plan skip_all => "Must run from 64-bit machine";
}
my $auto_execute = 0;
if ($auto_execute) {
    plan tests => 75;
} else {
    plan tests => 385;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

#This should be removed when tests finish
my $tmp_dir;

my $model_name = "test_solexa_$ENV{USER}";
my $processing_profile_name = "test_solexa_pp_$ENV{USER}";
my $subject_name = 'H_GV-933124G-skin1-9017g';
my $subject_type = 'sample_name';
my @read_sets = setup_test_data($subject_name);

my $add_reads_test = Genome::Model::Command::Build::ReferenceAlignment::Test->new(
    model_name => $model_name,
    subject_name => $subject_name,
    subject_type => $subject_type,
    processing_profile_name => $processing_profile_name,
    auto_execute => $auto_execute,
    read_sets => \@read_sets,
    tmp_dir => $tmp_dir,
);
isa_ok($add_reads_test,'Genome::Model::Command::Build::ReferenceAlignment::Test');

$add_reads_test->create_test_pp(
                                sequencing_platform => 'solexa',
    name => $processing_profile_name,
    dna_type => 'genomic dna',
    align_dist_threshold => '0',
    multi_read_fragment_strategy => 'eliminate start site duplicates',
    indel_finder_name => 'maq0_6_5',
    genotyper_name => 'maq0_6_5',
    read_aligner_name => 'maq0_6_5',
    reference_sequence_name => 'refseq-for-test',
    #filter_ruleset_name => 'basic',
);

$add_reads_test->runtests;

exit;

sub setup_test_data {
    my $subject_name = shift;
    my @read_sets;
    ####If we have a test gzip of files, we need to unzip it here

    ####Maybe create Genome::RunChunk(s)?
    ###teh gzips are teh key here.... DR. SCHUSTE has provided us with some suitably tiny fastqs in gzip form.
    use FindBin qw($Bin);

    $tmp_dir = File::Temp::tempdir();
    chdir $tmp_dir;
    my $zip_file = '/gsc/var/cache/testsuite/data/Genome-Model-Command-AddReads/addreads.tgz';
    `tar -xzf $zip_file`;

    #$tmp_dir = '/tmp/fake-gerald';
    my @run_dirs = grep { -d $_ } glob("$tmp_dir/*_*_*_*");
    my $seq_id = -10;
    for my $run_dir (@run_dirs) {
        my $run_dir_params = GSC::PSE::SolexaSequencing::SolexaRunDirectory->parse_regular_run_directory($run_dir);
        #print Dumper $run_dir_params;
        for my $lane (1 .. 8) {
            my $sls = GSC::RunLaneSolexa->create(
                #id                         => $seq_id--,
                run_name                   => $$run_dir_params{'run_name'},
                lane                       => $lane,
                full_path                  => $run_dir,
                flow_cell_id               => $$run_dir_params{'flow_cell_id'},
                sample_name                => $subject_name,
                clusters_avg               => -1,
                clusters_stdev             => -1,
                filt_aligned_clusters_pct  => -1,
                filt_aligned_clusters_stdev=> -1,
                clusters                   => 1,
                filt_clusters              => -1,
                filt_clusters_avg          => -1,
                filt_clusters_stdev        => -1,
                filt_error_rate_avg        => -1,
                filt_error_rate_stdev      => -1,
                first_cycle_inten_avg      => -1,
                first_cycle_inten_stdev    => -1,
                inten_after_20_cycles_pct  => -1,
                inten_after_20_cycles_stdev=> -1,
                inten_avg                  => -1,
                inten_stdev                => -1,
                kilobases_read             => -1,
                phasing_pct                => -1,
                prephasing_pct             => -1,
                is_external                => 0,
                clusters                   => -1,
                #these need to be valid for metric generation
                filt_clusters                   => 5000000,
                read_length                => 32, 
                #seq_id                     => -1,
                sral_id                    => -1,
                library_name => 'TESTINGLIBRARY',
                gerald_directory           => $run_dir,
                is_external => 0,    
            );
            #next;
            
            my @files = grep { -e $_ } glob("$run_dir/${lane}_*.fastq");
            foreach my $file (@files) {
                $file =~ /sequence\.(.*)\.sorted/;
                my $fs_path = GSC::SeqFPath->create(
                                                    path => $file ,
                                                    seq_id => $sls->seq_id,
                                                    data_type => $1  .' fastq path',
                                                    creation_event_id => -1,
                                                );
            }
            push @read_sets, $sls;

            my $instrument_data = Genome::InstrumentData->create_mock(
                                                                      id => $sls->seq_id,
                                                                      sequencing_platform => 'solexa',
                                                                      sample_name => $sls->sample_name,
                                                                      run_name => $sls->run_name,
                                                                  );
        }
    }
    #UR::Context->_sync_databases();
    return @read_sets;
}

1;
