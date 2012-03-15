#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 22;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use above "Genome";
use Genome::Model;
use Genome::Model::Build;

# used for everything below which requires a name
my $tname = "test-new-processing-profile";

# create a new sample
my $s = Genome::Sample->create(name => $tname);
my $lib = Genome::Library->create(sample => $s, name => $s->name . '-lib1');
ok($s, "made a sample on which to test");

my $temp_directory = Genome::Sys->create_temp_directory();

# create new imported instrument data
my $i = Genome::InstrumentData::Imported->create(
    library_id=> $lib->id, 
    original_data_path => $temp_directory,
    import_format => 'sanger fastq',
    sequencing_platform => 'solexa',
);
ok($i, "made instrument data for the sample");

# define a processing profile subclass for this pipeline
class Genome::ProcessingProfile::Foo {
    is => 'Genome::ProcessingProfile',
    has_param => [
        p1 => { doc => 'param 1' },
        p2 => { doc => 'param 2' },
        p3 => { is => 'Genome::Sample', is_optional => 1, doc => 'param 3' },
    ]
};

my $execute_build;
sub Genome::ProcessingProfile::Foo::_execute_build { $execute_build = $_[1]; 1; };

ok(Genome::ProcessingProfile::Foo->can("get"), "defined a new class of processing profile");
ok(Genome::Model::Foo->can('get'), "the corresponding model class auto generates");
ok(Genome::Model::Build::Foo->can('get'), "the corresponding build class auto generates");

# make a profile mixing scalar params and objects
my $p0 = Genome::ProcessingProfile::Foo->create(
    name => $tname,
    p1 => 'value1', 
    p2 => 'value2',
    p3 => $s
);
ok($p0, "made a new profile");
is($p0->name, $tname, "got back name");
is($p0->p1, 'value1', "got back p1 value 'value1'");
is($p0->p2, 'value2', "got back p2 value 'value2'");
is($p0->p3, $s, "got back p3 value $s");
$p0->delete;
isa_ok($p0, 'UR::DeletedRef', "deleted test processing profile successfully");

# make an initial processing profile with a given set of parameter values 
my $p = Genome::ProcessingProfile::Foo->create(
    name => $tname,
    p1 => 'value1', 
    p2 => 'value2'
);
ok($p, "made a new processing profile");

# define a model of the sample with that profile
# $p->add_model($sample) == $sample->add_model($p) == Genome::Model->create(subject => $s, processing_profile => $p);
my $m = $p->add_model(
    name                => $tname,
    subject_id          => $s->id,
    subject_class_name  => $s->class,
);
ok($m, "made a new model");
isa_ok($m,'Genome::Model::Foo',"the model is of the correct subclass");

# add instrument data
my $a = $m->add_instrument_data($i);
ok($a, "added instrument data to the model");

# add other input
my $n = $m->add_input(name => "foo", value_class_name => "UR::Value", value_id => "123");
ok($n, "added a misc input to the model");

# verify both inputs
my @mi = $m->inputs;
is(scalar(@mi),2, "found two model inputs");

# create a build

my $b = $m->add_build(data_directory => $temp_directory);
ok($b, "created a new build");

# start it, which in our case will run it completely...
ok($b->start(server_dispatch => 'inline', job_dispatch => 'inline'), "build started");

# examine the build
is($execute_build,$b,"the build execution logic ran");
is($b->status,'Succeeded',"the build status is Succeeded");
ok(-d $b->data_directory, "the data directory " . $b->data_directory . " is present");

