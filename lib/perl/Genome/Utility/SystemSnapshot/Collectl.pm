package Genome::Utility::SystemSnapshot::Collectl;

use Storable;
use Data::Dumper;

use base qw(Genome::Utility::SystemSnapshot);
use Genome::Utility::AsyncFileSystem;
use File::Copy;

use strict;
use warnings;

sub new {
  my $class = shift;
  my $output = shift;
  my $self = {
    'output' => 'collectl.output.txt',
    'tempfile' => undef,
    'pid' => undef,
    'cv' => undef,
  };
  if (defined $output) {
    $self->{output} = $output;
  }
  bless $self, $class;
  return $self;
}

sub _sleep {
  # Use an event timer to sleep within the event loop
  my $self = shift;
  my $seconds = shift;
  my $sleep_cv = AnyEvent->condvar;
  my $w = AnyEvent->timer(
      after => $seconds,
      cb => $sleep_cv
  );
  $sleep_cv->recv;
}

sub start {
  my $self = shift;
  my $collectl_cmd = "/usr/bin/collectl";
  if (! -x $collectl_cmd) {
    warn "comand not found: $collectl_cmd: NOT profiling";
    return;
  }
  # Note that collectl 3.4.3 butchers export filenames, removing letter "l"
  # It defaults to the letter L for format lexpr
  my $collectl_args = "--all --export lexpr -f /tmp -on";

  # Add a command to a condition variable event loop.
  # This gets started by our caller's use of $cmd_cv->recv;
  # Note that we unset PERL5LIB to ensure that we are using the
  # correct perl for collectl, in this case /gsc/bin/perl.
  $self->{cv} = Genome::Utility::AsyncFileSystem->shellcmd(
      cmd => "$collectl_cmd $collectl_args",
      '$$' => \( $self->{pid} ),
      close_all => 1,
      on_prepare => sub { delete $ENV{PERL5LIB} },
      allow_failed_exit_code => 1,
  );
  # Give collectl time to start up
  $self->_sleep(2);
}

sub stop {
  my $self = shift;

  # Now that cmd_cv->cmd status is true, we're back, and we send SIGTERM to collectl's pid.
  kill 15, $self->{pid};
  # Now recv on that condition variable, which will catch the signal and exit.
  # We wrap in eval and examine $@ to ensure we catch the signal we sent, but we can still
  # observe any unexpected events.
  eval {
    $self->{cv}->recv;
  };
  #if (defined $@ && $@ !~ /^COMMAND KILLED\. Signal 15/) {
  if ($@) {
    # unexpected death message from shellcmd.
    die $@;
  }
  move "/tmp/L", $self->{output} or die "Failed to move collectl output file /tmp/L to $self->{output}: $!";
}

sub report {
  my $self = shift;
  my $metrics;

  open S, "<$self->{output}" or die "Unable to open collectl output file: $self->{output}: $!";
  my @lines = <S>;
  close S;
  foreach my $line (@lines) {
    chomp $line;
    my ($metric,$value) = split(' ',$line);
    $metrics->{$metric} = $value;
  }
  return $metrics;
}

1;
