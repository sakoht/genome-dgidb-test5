#!/gsc/bin/perl

use strict;
use warnings;

use Test::More;
use File::Compare;

use above 'Genome';

BEGIN {
    if (`uname -a` =~ /x86_64/){
        plan tests => 4;
    } else{
        plan skip_all => 'Must run on a 64 bit machine';
    }
    use_ok('Genome::Model::Tools::Maq::MapToLayers');
}

my $map_file = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Maq-Map/2.map';
my $expected_layers_file = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-Maq-Map/2.map.layers';
my $tmp_dir = File::Temp::tempdir('Map-To-Layers-'. $ENV{USER} .'-XXXX', DIR => '/gsc/var/cache/testsuite/running_testsuites', CLEANUP => 1);
my $cmd = Genome::Model::Tools::Maq::MapToLayers->create(
                                                         map_file => $map_file,
                                                         layers_file => $tmp_dir .'/2.layers',
                                                     );
isa_ok($cmd,'Genome::Model::Tools::Maq::MapToLayers');
ok($cmd->execute,'execute command '. $cmd->command_name);
ok(!compare($expected_layers_file,$cmd->layers_file),'layers file matches expected');

exit;
