#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';
use Test::More;

use_ok('Genome::Model::Tools::ViromeEvent::BlastX_NT::PoolAndSplitSequence');

#check testsuite files/dirs
my $data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-ViromeScreening/Titanium17';
ok( -d $data_dir, "Testsuite data dir exists" ) or die;

my $run = 'Titanium17';
my $sample_name = $run.'_undecodable';
my $input_file = $sample_name.'.HGfiltered.fa';
my $prev_blast_dir = $sample_name.'.HGfiltered_BLASTN';
my $curr_blast_dir = $sample_name.'.BNFiltered_TBLASTX_nt';

#copy/link files
my $temp_dir = Genome::Utility::FileSystem->create_temp_directory();
ok( -d $temp_dir, "Created temp test dir" ) or die;

Genome::Utility::FileSystem->create_directory( $temp_dir."/$run" );
ok( -d $temp_dir."/$run", "Created temp run dir" );

Genome::Utility::FileSystem->create_directory( $temp_dir."/$run/$sample_name" );
ok( -d $temp_dir."/$run/$sample_name", "Created temp sample dir" );

symlink( $data_dir."/$sample_name/$input_file", $temp_dir."/$run/$sample_name/$input_file" );
ok( -l $temp_dir."/$run/$sample_name/$input_file", "Linked sample file" );

symlink( $data_dir."/$sample_name/$prev_blast_dir", $temp_dir."/$run/$sample_name/$prev_blast_dir" );
ok( -l $temp_dir."/$run/$sample_name/$prev_blast_dir", "Linked previous blast dir" );

#create/execute tool
my $c = Genome::Model::Tools::ViromeEvent::BlastX_NT::PoolAndSplitSequence->create(
    dir     => $temp_dir."/$run/$sample_name",
    logfile => $temp_dir.'/log.txt',
    );

ok( $c, "Created blastN pool and split sequences event" ) or die;

ok( $c->execute, "Successfully executed event" ) or die;

ok( -s $temp_dir."/$run/$sample_name/$curr_blast_dir/$sample_name".'.BNFiltered.fa_file0.fa', "Created pooled file" );

#<STDIN>;

done_testing();

exit;
