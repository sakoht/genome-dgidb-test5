#!/usr/bin/env perl

use strict;
use warnings;

use above 'Genome';

use Test::More;

use_ok('Genome::Model::Tools::Sx::SeqReader') or die;
use_ok('Genome::Model::Tools::Sx::SeqWriter') or die;

class Genome::Model::Tools::Sx::SeqReaderTest {
    is => 'Genome::Model::Tools::Sx::SeqReader',
};
sub Genome::Model::Tools::Sx::SeqReaderTest::read {
    my $self = shift;
    isa_ok($self->{_file}, 'IO::File');
    my $line = $self->{_file}->getline;
    is($line, "NOOP\n", 'read: line is "NOOP\n"');
    return 1;
}

class Genome::Model::Tools::Sx::SeqWriterTest {
    is => 'Genome::Model::Tools::Sx::SeqWriter',
};
sub Genome::Model::Tools::Sx::SeqWriterTest::write {
    my ($self, $seq) = @_;
    isa_ok($self->{_file}, 'IO::File');
    $self->{_file}->print("NOOP\n"); # just to give the file size
    return 1;
}

is_deeply([map { $_->property_name } Genome::Model::Tools::Sx::SeqReaderTest->_file_properties], [qw/ file /], 'reader file properties');
is_deeply([map { $_->property_name } Genome::Model::Tools::Sx::SeqWriterTest->_file_properties], [qw/ file /], 'writer file properties');

my $failed_create = Genome::Model::Tools::Sx::SeqWriterTest->create;
ok(!$failed_create, 'Failed to create w/ writer w/o file');
$failed_create = Genome::Model::Tools::Sx::SeqReaderTest->create;
ok(!$failed_create, 'Failed to create w/ reader w/o file');

my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
my $file = $tmpdir.'/seqs';
my $w = Genome::Model::Tools::Sx::SeqWriterTest->create(name => 'abe lincoln', file => $file);
ok($w, 'create writer');
is($w->mode, 'w', 'mode is (w)rite');
ok($w->write, 'write');
ok($w->flush, 'flush');
my $r = Genome::Model::Tools::Sx::SeqReaderTest->create(file => $file);
ok($r, 'create reader');
ok($r->read, 'read');

$failed_create = Genome::Model::Tools::Sx::SeqWriterTest->create(name => 'abe lincoln', file => $file);
ok(!$failed_create, 'failed to recreate writer in (w)rite mode for existing file');

$w = Genome::Model::Tools::Sx::SeqWriterTest->create(name => 'abe lincoln', file => $file, mode => 'a');
ok($w, 'create writer');
is($w->mode, 'a', 'mode is (a)ppend');
ok($w->write, 'write');
ok($r->read, 'read after append');

done_testing();
exit;

