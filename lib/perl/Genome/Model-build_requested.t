#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

# Create test subclasses of model and processing profile that can be easily instantiated
class Genome::Model::Test {
    is => 'Genome::Model',
};

class Genome::ProcessingProfile::Test {
    is => 'Genome::ProcessingProfile',
};

# Make test sample, processing profile, and model
my $sample = Genome::Sample->create(
    name => 'dummy test sample',
);
ok($sample, 'created test sample') or die;

my $pp = Genome::ProcessingProfile::Test->create(
    name => 'dummy processing profile',
);
ok($pp, 'created test processing profile') or die;

my $model = Genome::Model::Test->create(
    subject_id => $sample->id,
    subject_class_name => $sample->class,
    processing_profile_id => $pp->id,
    name => 'test model',
);
ok($model, 'created test model') or die;

# Set build requested without a reason
$model->build_requested(1);
is($model->build_requested, 1, 'build requested successfully set');

my @notes = $model->notes;
ok(@notes == 1, 'found exactly one build requested note');
is($notes[0]->header_text, 'build_requested', 'note is the build requested note');
is($notes[0]->body_text, 'no reason given', 'note body is default, as expected when no reason is given');

# Set build requested back to false
$model->build_requested(0);
is($model->build_requested, 0, 'unset build requested');
@notes = $model->notes;
ok(@notes == 2, 'retrieved two build requested notes, as expected');

# Now set it again with a reason provided
$model->build_requested(1, 'test build');
is($model->build_requested, 1, 'set build requested with reason provided');

@notes = $model->notes;
ok(@notes == 3, 'retrieved two build requested notes, as expected');

my $note = $model->latest_build_request_note;
is($note->header_text, 'build_requested', 'header of new note is build_requested');
is($note->body_text, 'test build', 'body of new note set to expected value');

done_testing();



