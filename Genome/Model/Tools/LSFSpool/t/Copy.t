# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl LSFSpool.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 12;
use Test::Output;
use Test::Exception;

use Data::Dumper;
use Cwd;
use File::Basename;

BEGIN { use_ok('Genome::Model::Tools::LSFSpool') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

sub test_start {
  # Instantiate an LSFSpool object to test.
  my $obj = create Genome::Model::Tools::LSFSpool;
  $obj->{debug} = 1;
  $obj->prepare_logger();
  return $obj;
}

sub test_logger {
  my $obj = shift;
  $obj->{configfile} = $cwd . "/data/lsf_spool_trivial.cfg";
  $obj->read_config();
  $obj->activate_suite();
  $obj->{debug} = 1;
  stdout_like { $obj->{suite}->logger("Test\n"); } qr/Test/, "logger with debug on ok";
  stdout_like { $obj->{suite}->local_debug("Test\n"); } qr/Test/, "debug on ok";
  $obj->{debug} = 0;
  stdout_like { $obj->{suite}->logger("Test\n"); } qr/Test/, "logger with debug off ok";
  $obj->{suite}->local_debug("Test\n");
  stdout_unlike { $obj->{suite}->local_debug("Test\n"); } qr/Test/, "debug off ok";
}

sub test_activate_suite {
  # test activate suite, the trivial one.
  my $obj = shift;
  my $params = "-f";
  my $dir = $cwd . "/data/spool/sample-fasta-1";
  my $file = "sample-fasta-1-1";
  $obj->{configfile} = $cwd . "/data/lsf_spool_trivial.cfg";
  $obj->read_config();
  $obj->activate_suite();
  is($obj->{config}->{suite}->{name},"Copy");
  my $command = $obj->{suite}->action($dir,$file);
  like($command,qr|^cp $params $dir/$file $dir/$file-output|,"comamnd returned ok");
  ok(-f "$dir/$file-output" == 1,"file is present");
  throws_ok { $obj->{suite}->action("bogusdir",$file) } qr/^given spool is not a directory/, "bad spool dir caught correctly";
  stdout_like { $obj->{suite}->logger("test\n") } qr/test/, "stdout logs 'test' ok";

  # simulate the action...
  open(OF,"$dir/$file-output") or die "cannot create simulated output file";
  close(OF);
  ok($obj->{suite}->is_complete("$dir/$file") == 1,"is_complete returns true");
  ok($obj->{suite}->is_complete("$dir/bogus") == 0,"is_complete returns false");
}

my $obj = test_start();
test_logger($obj);
test_activate_suite($obj);
