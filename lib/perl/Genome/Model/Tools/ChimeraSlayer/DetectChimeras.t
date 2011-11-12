#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';

use Data::Dumper 'Dumper';
use Test::More;
require File::Compare;

use_ok( 'Genome::Model::Tools::ChimeraSlayer::DetectChimeras' ) or die;

my $version = 1;
my $test_data_dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-ChimeraSlayer/DetectChimeras/v'.$version;
ok( -d $test_data_dir, 'Test data dir' );
my $sequences = $test_data_dir.'/chims.NAST';
ok( -s $sequences, 'Input sequences file' );

my $temp_test_dir = Genome::Sys->create_temp_directory();
ok( -d $temp_test_dir, 'Temp test dir' );
ok( File::Copy::copy($sequences, $temp_test_dir), 'Copied sequences file' );

my $cmd = Genome::Model::Tools::ChimeraSlayer::DetectChimeras->create(
    sequences => $temp_test_dir.'/chims.NAST',
    nastier_params => '-num_top_hits 10',
    chimera_slayer_params => '-windowSize 50 -printCSalignments -windowStep 5',
);
ok( $cmd, 'Created tool' );
ok( $cmd->execute, 'Executed tool' );


#check outputs
#files that should consistantly match
for my $file ( qw/ chims.NAST.out.CPS chims.NAST.out.CPS_RENAST / ) {
    ok( -s $temp_test_dir.'/'.$file, "Created file: $file" );
    ok( File::Compare::compare( $temp_test_dir.'/'.$file, $test_data_dir.'/'.$file ) == 0, "Test $file files match" );
}
#files that differ sometimes
 #chims.out.NAST.CPS.CPC.align
 #chims.out.NAST.CPS.CPC
 #chims.out.NAST.CPS.CPC.wTaxons
 #chims.out.NAST.CPS_RENAST
#binary files
 #chims.out.NAST.CPS_RENAST.cidx
 #chims.out.NAST.cidx

#<STDIN>;

done_testing();

exit;
