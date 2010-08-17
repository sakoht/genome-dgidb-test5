#!/usr/bin/env perl
use strict;
use warnings;

$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = "1";
$ENV{UR_DBI_NO_COMMIT} = "1";

use above "Genome";
#use Test::More tests => 2;
use Test::More skip_all => 'Broken Test -- FIXME'; 

my $i = Genome::InstrumentData::Command::Import::HmpSraProcess->create(
    path    => 'foo'
);
ok($i, "created the command object $i");
ok($i->execute,"executed the importer");

__END__

# The remaining tests are left from a copy of an older instrument data test that Scott used as the skeleton for this test...leaving them here as an example of the kinds of additional testing I need to add ... jmartin 100817

note "instrument data id is ". $i->import_instrument_data_id."\n";

my $i_d = Genome::InstrumentData::Imported->get($i->import_instrument_data_id);
is($i_d->sequencing_platform,'solexa','platform is correct');
is($i_d->user_name, $ENV{USER}, "user name is correct");
ok($i_d->import_date, "date is set");
is($i_d->reference_sequence_build_id, 103107618, "Reference sequence properly retreived, " . $i_d->reference_sequence_build_id. ".");

my $ok;
eval { $ok = UR::Context->_sync_databases(); };
ok($ok, "saves to the database!");

