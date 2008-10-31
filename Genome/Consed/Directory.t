#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 30;

use Genome::Consed::Directory;
use File::Path;

=cut
use Test::Mock;
# Mock up a processing profile
my $processing_profile = Test::MockObject->new();
$processing_profile->fake_module('Genome::ProcessingProfile');
$processing_profile->set_always('type_name', 'reference alignment');
=cut

my $path = "/tmp/consed_test_dir";

my $consed_dir = Genome::Consed::Directory->create(directory => $path);
ok (!$consed_dir, "Didn't create a Genome::Consed::Directory without an existing directory");

system "touch $path";
$consed_dir = Genome::Consed::Directory->create(directory => $path);
ok (!$consed_dir, "Didn't create a Genome::Consed::Directory with a non-directory");

unlink $path;

create_test_fixture();

$consed_dir = Genome::Consed::Directory->create(directory => $path);
ok ($consed_dir, "created a Genome::Consed::Directory");


my @directories = $consed_dir->directories;
ok ($directories[0] eq 'edit_dir' && $directories[1] eq 'phd_dir' && $directories[2] eq 'chromat_dir', "Got correct directories");

$consed_dir->create_consed_directory_structure;
ok(-d "$path/".$directories[0] && -d "$path/".$directories[0] && -d "$path/".$directories[0], "Created directory structure");

SKIP: {
    skip "These are not used and probably will be removed at some point... just have to remove the calls from the tree", 1, if 1;
}

destroy_test_fixture();

sub create_test_fixture {
    mkdir $path;
}

sub destroy_test_fixture {
    rmtree $path;    
}


