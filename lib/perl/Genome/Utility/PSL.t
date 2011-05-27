#!/usr/bin/env perl

use strict;
use warnings;

use above "Genome";

use Data::Dumper;

use Test::More tests => 6;
use Text::Diff;
use File::Temp;

use Genome::Utility::PSL::Reader;
use Genome::Utility::PSL::Writer;

my $test_dir = '/gsc/var/cache/testsuite/data/Genome-Utility-PSL';
my $file = "$test_dir/test.psl";

my $tmp_dir = File::Temp::tempdir(CLEANUP => 1);
my $out_file = "$tmp_dir/out.psl";

my $reader = Genome::Utility::PSL::Reader->create(
                                                   file => $file,
                                               );
isa_ok($reader,'Genome::Utility::PSL::Reader');
is($reader->separator,"\t",'separator');
is($reader->file,$file,'file accessor');

my $writer = Genome::Utility::PSL::Writer->create(
                                               file => $out_file,
                                           );
isa_ok($writer,'Genome::Utility::PSL::Writer');
is($writer->file,$out_file,'file accessor');
while (my $record = $reader->next) {
    $writer->write_record($record);
}
$writer->close;
$reader->close;

my $diff = diff($file,$out_file);
is($diff,'','Files are the same');


exit;
