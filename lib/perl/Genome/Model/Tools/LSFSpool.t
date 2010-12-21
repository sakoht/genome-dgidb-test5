
package LSFSpool::TestSuite;

my $CLASS = __PACKAGE__;

use base 'Test::Builder::Module';

use strict;
use warnings;

use Getopt::Std;

use Class::MOP;

#use Test::More tests => 70;
use Test::More skip_all => 'trying to write in code dir';
use Test::Output;
use Test::Exception;

use Data::Dumper;
use Cwd;
use File::Basename;
use File::Path;

#use Genome::Model::Tools::LSFSpool;
use above 'Genome';

my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

sub new {
  my $class = shift;
  my $self = {
    live => 0,
  };
  return bless $self, $class;
}

sub test_start {
  my $self = shift;
  # Instantiate an LSFSpool object to test.
  my $obj = create Genome::Model::Tools::LSFSpool;
  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_trivial.cfg";
  $obj->{debug} = 0;
  $obj->{dryrun} = 0;
  $obj->read_config();
  $obj->prepare_logger();
  $obj->activate_suite();
  $obj->find_progs();
  return $obj;
}

sub test_prepare_logger {
  my $self = shift;
  my $obj = create Genome::Model::Tools::LSFSpool;
  $obj->{debug} = 0;
  throws_ok { $obj->logger("Test\n"); } qr/no logfile defined/, "missing log check ok";
  $obj->prepare_logger();
  # Test prepare_logger, printing to STDOUT.
  $obj->{debug} = 1;
  stdout_like { $obj->logger("Test") } qr/^.*: Test/, "logger with debug on ok";
  stdout_like { $obj->local_debug("Test") } qr/^.*: Test/, "debug on ok";
  $obj->{debug} = 0;
  stdout_like { $obj->logger("Test") } qr/^.*: Test/, "logger with debug off ok";
  stdout_unlike { $obj->local_debug("Test") } qr/^.*: Test/, "debug off ok";
  $obj->DESTROY();
}

sub test_read_good_config_1 {
  my $self = shift;
  # Test a valid config.
  my $obj = create Genome::Model::Tools::LSFSpool;
  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_good_1.cfg";
  $obj->read_config();
  $obj->prepare_logger();
  is($obj->{config}->{queue},"backfill");
  ok($obj->{config}->{sleepval} == 60);
  ok($obj->{config}->{queueceiling} == 10000);
  ok($obj->{config}->{queuefloor} == 1000);
  ok($obj->{config}->{churnrate} == 30);
  ok($obj->{config}->{lsf_tries} == 2);
  ok($obj->{config}->{db_tries} == 5);
  $obj->DESTROY();
}

sub test_read_good_config_2 {
  my $self = shift;
  # Test a another valid config.
  my $obj = test_start();
  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_good_2.cfg";
  $obj->read_config();
  is($obj->{config}->{queue},"backfill");
  ok($obj->{config}->{sleepval} == 60);
  ok($obj->{config}->{queueceiling} == 10000);
  ok($obj->{config}->{queuefloor} == 1000);
  ok($obj->{config}->{churnrate} == 30);
  ok($obj->{config}->{lsf_tries} == 2);
  ok($obj->{config}->{db_tries} == 5);
  $obj->DESTROY();
}

sub test_read_bad_config {
  my $obj = create Genome::Model::Tools::LSFSpool;
  $obj->{debug} = 0;
  # Test an invalid config.
  $obj->{configfile} = undef;
  throws_ok { $obj->read_config() } qr/please specify a config file/, "no config throws exception ok";

  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_bad_2.cfg";
  throws_ok { $obj->read_config() } qr/configuration is missing required/, "missing config item throws exception ok";

  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_bad.cfg";
  throws_ok { $obj->read_config } qr/error loading config file/, "badly parsed config dies ok";
  $obj->DESTROY();
}

sub test_parsefile {
  my $self = shift;
  my $obj = test_start();

  my $dir = $cwd . "/LSFSpool/t/data";
  my $file = "seq-blast-spool-1-1";
  my $path = $dir . "/" . $file;
  my @res = $obj->parsefile($path);

  $file =~ /^.*-(\d+)/;
  my $base = basename dirname $path;
  my $number = $1;
  #my $array = "$base\[$number\]";
  my $array = $file;

  # This is the parent dir of the file
  ok($res[0] eq $dir, "spooldir ok");
  # This is the file
  ok($res[1] eq $file, "inputfile ok");
  # This is the job array: dir + number
  ok($res[2] eq $array, "job array ok");

  $file = "foo";
  $path = $dir . "/" . $file;
  throws_ok { $obj->parsefile($path); } qr/filename does not contain a number/, "bad filename caught ok";
  $obj->DESTROY();
}

sub test_parsedir {
  my $self = shift;
  my $obj = test_start();
  $obj->{debug} = 0;

  my $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1";
  my @res = $obj->parsedir($dir);
  ok($res[0] eq $cwd . '/LSFSpool/t/data/spool/sample-fasta-1',"dir ok");
  ok($res[1] eq 'sample-fasta-1-\\$LSB_JOBINDEX',"query ok");
  ok($res[2] eq 'sample-fasta-1[1-2]',"job array ok");
  $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-2";
  throws_ok { @res = $obj->parsedir($dir); } qr/spool.*contains no files/, "empty spool caught ok";
  $obj->DESTROY();
}

sub test_submit_job {
  my $self = shift;
  my $obj = $self->test_start();
  $obj->{debug} = 0;
  $obj->{dryrun} = 1;
  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_trivial.cfg";
  $obj->read_config();
  $obj->activate_suite();
  $obj->find_progs();

  my $id;
  my $file = "sample-fasta-1-1";
  my $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1/";
  $id = $obj->submit_job($dir);
  ok($id == 0);
  my $path = $dir . "/" . $file;
  $id = $obj->submit_job($path);
  ok($id == 0);
  $path = $cwd . "/LSFSpool/t/data/spool/sample-fasta-3/oddfile";
  throws_ok { $id = $obj->submit_job($path); } qr/filename does not contain a number/, "caught oddfile ok";

  $path = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1/bogus";
  throws_ok { $id = $obj->submit_job($path); } qr/argument is not a file or directory/, "caught bogus file ok";

  $path = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1";
  ok($obj->submit_job($path,1,0) == 0,"wait set ok");
  ok($obj->submit_job($path,0,1) == 0,"prio set ok");
  ok($obj->submit_job($path,1,1) == 0,"wait and prio set ok");

  $obj->{config}->{email} = 'user@genome.wustl.edu';
  stdout_like { $obj->submit_job($path); } qr/user\@genome.wustl.edu/, "email set ok";
  $obj->{config}->{email} = '';
  ok($obj->submit_job($path) == 0,"empty email set ok");
  delete $obj->{config}->{email};
  ok($obj->submit_job($path) == 0,"no email set ok");

  rmtree("$path.logs");

  $obj->DESTROY();
}

sub test_live_submit_job {

  my $self = shift;
  my $obj = $self->test_start();

  unless (defined $obj->{bsub} and $self->{live}) {
    SKIP: {
      skip "no bsub present or not live", 1;
    }
    return;
  }

  $obj->{debug} = 1;
  $obj->{config}->{queue} = "short";
  my $path = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1";
  my $file = "sample-fasta-1-1";
  my $id = $obj->submit_job("$path/$file");
  ok($id > 0,"bsub submits job id $id");
  #rmtree("$path.logs");

  $obj->DESTROY();
}

sub test_process {

  my $self = shift;
  my $obj = create Genome::Model::Tools::LSFSpool;
  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_trivial-2.cfg";
  $obj->{debug} = 1;
  $obj->{dryrun} = 0;
  $obj->read_config();
  $obj->prepare_logger();
  $obj->activate_suite();
  $obj->find_progs();

  unless (defined $obj->{bsub} and $self->{live}) {
    SKIP: {
      skip "no bsub present or not live", 1;
    }
    return;
  }

  $obj->{config}->{queue} = "short";
  $obj->{cachefile} = $cwd . "/LSFSpool/t/data/spool/sample-fasta-7.cache";
  unlink($obj->{cachefile});

  my $dir = $cwd  . "/LSFSpool/t/data/spool/sample-fasta-7";
  ok($obj->build_cache($dir) == 0);
  ok($obj->process_cache() == 0);

  unlink($obj->{cachefile});
  unlink("$dir/sample-fasta-7-1-output");
  unlink("$dir/sample-fasta-7-2-output");
  unlink("$dir/sample-fasta-7-3-output");
  rmtree("$dir.logs");
  $obj->DESTROY();
}

sub test_execute {

  my $self = shift;
  my $obj = create Genome::Model::Tools::LSFSpool;
  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_trivial-2.cfg";
  $obj->{debug} = 1;
  $obj->{dryrun} = 0;

  unless ($self->{live}) {
    SKIP: {
      skip "not live", 1;
    }
    return;
  }

  my $dir = $cwd  . "/LSFSpool/t/data/spool/sample-fasta-7";
  $obj->{cachefile} = $cwd . "/LSFSpool/t/data/spool/sample-fasta-7.cache";

  unlink($obj->{cachefile});
  unlink("$dir/sample-fasta-7-1-output");
  unlink("$dir/sample-fasta-7-2-output");
  unlink("$dir/sample-fasta-7-3-output");

  $obj->{spooldir} = $dir;

  ok($obj->execute() == 0);

  unlink($obj->{cachefile});
  unlink("$dir/sample-fasta-7-1-output");
  unlink("$dir/sample-fasta-7-2-output");
  unlink("$dir/sample-fasta-7-3-output");
  rmtree("$dir.logs");
  $obj->DESTROY();
}

sub test_check_queue {

  my $self = shift;
  my $obj = $self->test_start();

  unless (defined $obj->{bqueues} and $self->{live}) {
    SKIP: {
      skip "no bqueues present or not live", 1;
    }
    return;
  }

  $obj->{config}->{queue} = "short";
  $obj->{debug} = 1;
  my $path = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1/sample-fasta-1-1";
  my $full = $obj->check_queue();
  ok($full == -1 or $full == 0 or $full == 1);

  $obj->{config}->{queueceiling} = 1;
  $obj->{config}->{queuefloor} = 0;
  $obj->{config}->{queue} = "long";
  $full = $obj->check_queue();
  ok($full == -1 or $full == 0 or $full == 1);

  $obj->{config}->{queueceiling} = 10000;
  $obj->{config}->{queuefloor} = 1000;
  $obj->{config}->{queue} = "backfill";
  $full = $obj->check_queue();
  ok($full == -1 or $full == 0 or $full == 1);

  $obj->DESTROY();
}

sub test_waitforjobs {

  my $self = shift;
  my $obj = $self->test_start();

  $obj->{debug} = 1;
  my $path = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1/sample-fasta-1-1";
  lives_ok { $obj->check_running($path); } "check_running ran ok";
  lives_ok { $obj->waitforjobs($path); } "waitforjobs ran ok";
  $obj->DESTROY();
}

sub test_check_cwd {
  my $self = shift;
  my $obj = test_start();
  $obj->{debug} = 0;
  $obj->{dryrun} = 1;
  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_good_1.cfg";
  $obj->read_config();
  $obj->activate_suite();

  my $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1";
  my $res = $obj->check_cwd($dir);
  ok($res  == 1);
  $dir = $cwd . "/LSFSpool/t/data/spool";
  throws_ok { $obj->check_cwd($dir); } qr/spool directory \S+ has unexpected/, "spotted bad spool ok";
  $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-3";
  throws_ok { $obj->check_cwd($dir); } qr/spool directory \S+ has unexpected/, "spotted bad spool ok";
  $obj->DESTROY();
}

sub test_find_progs {
  my $self = shift;
  # Test the find_progs() subroutine.
  my $obj = test_start();
  ok($obj->find_progs() == 0);
  like($obj->{bsub},qr/^.*\/bsub/,"bsub is found");
  like($obj->{bqueues},qr/^.*\/bqueues/,"bqueues is found");
  $obj->DESTROY();
}

sub test_finddirs {
  my $self = shift;
  my $obj = test_start();
  my $dir = $cwd . "/LSFSpool/t/data";
  my @res = $obj->finddirs($dir);
  lives_ok { $obj->finddirs($dir); } "finddirs lives ok";
  $obj->DESTROY();
}

sub test_findfiles {
  my $self = shift;
  my $obj = test_start();
  my $dir = $cwd . "/LSFSpool/t/data";
  lives_ok { $obj->findfiles($dir); } "findfiles lives ok";
  my $file = $dir . "/spool/sample-fasta-1/sample-fasta-1-1";
  my @res = $obj->findfiles($file);
  ok($res[0] eq $file,"single file returned ok");
  $obj->DESTROY();
}

sub test_build_cache {
  my $self = shift;
  # Test cache building.
  my @res;
  my $obj = create Genome::Model::Tools::LSFSpool;

  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_good_1.cfg";
  $obj->{debug} = 0;
  $obj->{buildonly} = 1;
  $obj->prepare_logger();
  $obj->read_config();
  $obj->activate_suite();

  my $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1";
  $obj->build_cache($dir);

  @res = $obj->{cache}->fetch($dir,'count');
  ok($res[0] == 0,"'count' is correctly 0");
  @res = $obj->{cache}->fetch_complete(0);
  ok($res[0] eq $dir,"'fetch_complete' correctly fetches dir");
  @res = $obj->{cache}->fetch($dir,'spoolname');
  ok($res[0] eq $dir,"'spoolname' is correct");
  unlink($obj->{cachefile});
  rmtree("$dir.logs");
  $obj->DESTROY();
}

sub test_activate_suite {
  my $self = shift;
  # test activate suite, the trivial one.
  my $obj = $self->test_start();
  my $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-1";
  my $file = "sample-fasta-1-1";
  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_trivial.cfg";
  $obj->read_config();
  $obj->activate_suite();
  is($obj->{config}->{suite}->{name},"Copy");
  $obj->{suite}->action($dir,$file);
  ok(-f "$dir/$file-output" == 1);
  throws_ok { $obj->{suite}->action("bogusdir",$file) } qr/^given spool is not a directory/, "bad spool dir caught correctly";

  open(OF,"$dir/$file-output") or die "cannot create simulated output file";
  close(OF);
  $obj->{suite}->logger("test\n");
  ok($obj->{suite}->is_complete("$dir/$file") == 1,"is_complete returns true");
  ok($obj->{suite}->is_complete("$dir/bogus") == 0,"is_complete returns false");
  $obj->DESTROY();
}

sub test_validate {
  my $self = shift;
  my $obj = $self->test_start();
  $obj->{configfile} = "$cwd/LSFSpool/t/data/lsf_spool_good_1.cfg";
  $obj->read_config();
  $obj->prepare_logger();
  $obj->activate_suite();

  $obj->{debug} = 1;

  my $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-2";
  my ($complete,@files);
  lives_ok { ($complete,@files) = $obj->validate($dir); } "validate runs ok";
  ok($complete == -1,"empty spool spotted ok");
  is_deeply ([sort @files], [],"empty spool spotted ok");

  $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-5";
  ($complete,@files) = $obj->validate($dir);
  ok($complete == 1,"complete spool spotted ok");
  is_deeply (sort [@files], [],"complete spool spotted ok");

  $dir = $cwd . "/LSFSpool/t/data/spool/sample-fasta-6";
  ($complete,@files) = $obj->validate($dir);
  ok($complete == 0,"incomplete spool spotted ok");
  my @expected = ("sample-fasta-6-3");
  is_deeply (sort [@files], sort [@expected],"incomplete spool spotted ok");

  $obj->DESTROY();
}

sub main {
  my $self = shift;
  $self->test_prepare_logger();
  $self->test_parsefile();
  $self->test_parsedir();
  $self->test_submit_job();
  $self->test_finddirs();
  $self->test_findfiles();
  $self->test_check_cwd();
  $self->test_find_progs();
  $self->test_read_good_config_1();
  $self->test_read_good_config_2();
  $self->test_read_bad_config();
  $self->test_activate_suite();
  $self->test_build_cache();
  $self->test_validate();
  $self->test_waitforjobs();
  $self->test_check_queue();
  $self->test_live_submit_job();
  $self->test_process();
  $self->test_execute();
}

# MAIN
my $opts = {};
getopts("lL",$opts) or
  throw("failure parsing options: $!");

my $Test = $CLASS->new();

# Run "live tests" that actually bsub.
if ($opts->{'L'}) {
  $Test->{live} = 1;
}

if ($opts->{'l'}) {
  print "Display list of tests\n\n";
  my $meta = Class::MOP::Class->initialize('LSFSpool::TestSuite');
  foreach my $method ($meta->get_all_methods()) {
    if ($method->name =~ m/^test_/) {
      print $method->name . "\n";
    }
  }
  exit;
}

if (@ARGV) {
  my $test = $ARGV[0];
  if ($Test->can($test)) {
    print "Run $test\n";
    $Test->$test();
  } else {
    print "No test $test known\n";
  }
} else {
  print "run all tests\n";
  $Test->main();
}

1;
