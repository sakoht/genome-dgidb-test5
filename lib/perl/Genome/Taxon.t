#!/usr/bin/env perl
use strict;
use warnings;

use above "Genome";
use Test::More;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

UR::DataSource->next_dummy_autogenerated_id;
do {
    $UR::DataSource::last_dummy_autogenerated_id = int($UR::DataSource::last_dummy_autogenerated_id / 10);
} until length($UR::DataSource::last_dummy_autogenerated_id) < 9;
diag('Dummy ID: '.$UR::DataSource::last_dummy_autogenerated_id);
cmp_ok(length($UR::DataSource::last_dummy_autogenerated_id), '<',  9, 'dummy id is shorter than 9 chars');

use_ok('Genome::Taxon');

my $id = -54321;
my $taxon = Genome::Taxon->get($id);
ok(!$taxon, 'taxon does not exist');

$taxon = Genome::Taxon->create(
    name => 'Wookiee',
    domain => 'Unknown',
    strain_name => 'Short Hair',
    species_latin_name => 'Kashyyyk Wookiee',
    estimated_genome_size => 7000000000,
);
ok($taxon, "created a new genome taxon");
isa_ok($taxon, 'Genome::Taxon');
ok($taxon->id, "id is set");
is($taxon->subject_type, 'species_name', 'subject type is species_name');
print Data::Dumper::Dumper($taxon);

my $commit = eval{ UR::Context->commit; };
ok($commit, 'commit');

$taxon = Genome::Taxon->get(name => 'Wookiee');
ok($taxon, 'got new taxon');

done_testing();
exit();

