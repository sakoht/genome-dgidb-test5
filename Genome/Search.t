#!/gsc/bin/perl

use strict;
use warnings;

BEGIN {
$ENV{UR_DBI_NO_COMMIT} = 1; #Important! A UR commit hook is tested below
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above "Genome";
use Genome::Utility::TestBase;
use Test::More tests => 10;

### Tests adding/removing documents

my $individual = Genome::Individual->create(
    common_name => 'search_test_1',
    name => 'search_test_1',
    gender => 'Female',
);

#Test commit hook
ok(UR::Context->commit, 'commit did not crash');

#Manually get Solr document (duplicates what should have happened in commit hook test)
my $individual_doc = Genome::Search->resolve_document_for_object($individual);
ok($individual_doc, 'got a document for test individual');

ok($individual->delete, 'delete did not crash');
ok(UR::Context->rollback, 'rollback did not crash');

### Tests for search class resolver

#Simple case
my $individual_class = Genome::Search->_resolve_subclass_for_object( Genome::Individual->create() );
is($individual_class, 'Genome::Search::Individual', 'found proper search class for an individual');

#Search class belongs to parent
my $model = Genome::Model->get(2771359026);
my $model_class = Genome::Search->_resolve_subclass_for_object($model); #Model ID mentioned in ReferenceAlignment.t
is($model_class, 'Genome::Search::Model', 'found proper search class for a model subtype');

#Class outside Genome namespace
my $solexa_run_class = Genome::Search->_resolve_subclass_for_object(GSC::Equipment::Solexa::Run->create());
is($solexa_run_class, 'Genome::Search::GSC::Equipment::Solexa::Run', 'found proper search class for a solexa run');

#Class not being indexed
my $iub_class = Genome::Search->_resolve_subclass_for_object(bless {}, 'Genome::Info::IUB');
is($iub_class, undef, 'returned no search class for IUB info module');

#Class not being indexed though a class up the directory structure is
my $build_class = Genome::Search->_resolve_subclass_for_object(Genome::Model::Somatic::Report::Variant->create( build_id => 97848505)); #Build ID mentioned in ReferenceAlignment.t
is($build_class, undef, 'returned no search class for a somatic model variant report');

#Not a blessed reference
my $hash_class = Genome::Search->_resolve_subclass_for_object({ hashkey => 'hashvalue'});
is($hash_class, undef, 'returned no search class for an unblessed hash');

