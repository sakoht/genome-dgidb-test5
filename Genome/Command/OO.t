#!/usr/bin/env perl
use strict;
use warnings;
BEGIN { $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1 };
use above "Genome";
use Test::More tests => 6;
my $v;

class Genome::ProcessingProfile::Foo { is => 'Genome::ProcessingProfile' };

my $p = Genome::ProcessingProfile::Foo->create(name => "profile1");
ok($p, 'made a profile');

my $s = Genome::Sample->create(name => 'sample1');
ok($s, 'made a sample');

my @p = (processing_profile => $p, subject_class_name => ref($s), subject_id => $s);

my $m1 = Genome::Model::Foo->create(@p, name => 'model1');
ok($m1, "made a model $m1");
my $m2 = Genome::Model::Foo->create(@p, name => 'model2');
ok($m1, "made a model $m2");
my $m3 = Genome::Model::Foo->create(@p, name => 'model3');
ok($m1, "made a model $m3");

class Genome::Model::Command::T1 {
    is => 'Genome::Command::OO',
    has => [
        model => { is => 'Genome::Model', id_by => 'model_id' },
    ]
};
sub Genome::Model::Command::T1::execute {
    my $self = shift;
    $v = $self->model;
    #print ">>$v<<\n";
    return 1;
}

my @v;
class Genome::Model::Command::T2 {
    is => 'Genome::Command::OO',
    has_many => [
        models => { is => 'Genome::Model' },
    ]
};
sub Genome::Model::Command::T2::execute {
    my $self = shift;
    @v = $self->models;
    return 1;
}

sh("genome model t1 --model model1");
is($v, $m1, "got single model with full name");

sub sh {
    my $txt = shift;
    my @w = split(/\s+/,$txt);
    shift @w;
    my $e = Genome::Command->_execute_with_shell_params_and_return_exit_code(@w);
    die if $e;
}

__END__
my $e = Genome::Command->_execute_with_shell_params_and_return_exit_code(
    'model t1  
);
