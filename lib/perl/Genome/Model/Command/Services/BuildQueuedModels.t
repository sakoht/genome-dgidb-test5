#!/gsc/bin/perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use above 'Genome';

use Data::Dumper 'Dumper';
use Genome::Utility::TestBase;
use Test::MockObject;
use Test::More;

use_ok('Genome::Model::Command::Services::BuildQueuedModels') or die;

# mock dem models
my @models;
for my $id (1..3) {
    my $model = Test::MockObject->new();
    $model->set_always('id', $id);
    $model->mock(
        'build_requested',
        sub{ 
            my ($self, $build_requested) = @_;
            if ( defined $build_requested ) {
                $self->{build_requested} = $build_requested;
            }
            return $self->{build_requested};
        }
    );
    $model->set_always('__display_name__', "Mocked Model $id");
    $model->build_requested($id % 2); 
    push @models, $model;
}
ok(@models, 'created mock models');

# overload models get, locking and shellcmd during tests
no warnings;
*Genome::Model::get = sub{ return grep { $_->build_requested } @models; };
*Genome::Sys::shellcmd = sub{
    my $class = shift;
    my %params = @_;
    my $line = $params{cmd};

    unless($line) {
        return -1;
    }

    my $id = (split(/\s+/, $line))[-1];
    if($id) {
        my ($model) = grep( $_->id eq $id, @models);
        $model->build_requested(0); #Simulate starting the build
    } else {
        die 'Could not find id in line: ' . $line;
    }
};
*Genome::Sys::lock_resource = sub{ return 1; };
*Genome::Sys::unlock_resource= sub{ return 1; };
use warnings;

is_deeply([ Genome::Model->get ], [ $models[0], $models[2] ], 'models get overloaded') or die;
ok(Genome::Sys->lock_resource, 'lock_resource overloaded') or die;
ok(Genome::Sys->unlock_resource, 'unlock_resource overloaded') or die;
ok(Genome::Sys->shellcmd, 'shellcmd overloaded') or die;

my $command_1 = Genome::Model::Command::Services::BuildQueuedModels->create();
isa_ok($command_1, 'Genome::Model::Command::Services::BuildQueuedModels');
ok($command_1->execute(), 'executed build command');
is($command_1->_builds_started, 2, 'started builds for the two applicable models');
is_deeply([ map { $_->build_requested } @models ], [qw/ 0 0 0 /], 'builds no longer requested for models');

my $command_2 = Genome::Model::Command::Services::BuildQueuedModels->create();
isa_ok($command_2, 'Genome::Model::Command::Services::BuildQueuedModels');
ok($command_2->execute(), 'executed build command');
is($command_2->_builds_started, 0, 'started no builds since no applicable models');

done_testing();
exit;
