#! /gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

use Test::Class;

Test::Class->runtests(qw/ GenomeUtilityFileSystem::Test /);

exit 0;

#####################################################

package GenomeUtilityFileSystem::Test;

use base 'Test::Class';

use Data::Dumper;
use File::Path;
use Test::More;

sub startup : Test(startup => 1) {
    require_ok('Genome::Utility::FileSystem');
}

sub _base_test_dir {
    return '/gsc/var/cache/testsuite/data/Genome-Utility-Filesystem';
}

sub test0_open_directory : Test(5) {
    my $self = shift;

    # Real dir
    my $dh = Genome::Utility::FileSystem->open_directory(_base_test_dir());
    ok($dh, "Opened dir: "._base_test_dir());
    isa_ok($dh, 'IO::Dir');

    # No dir
    ok(!Genome::Utility::FileSystem->open_directory, 'Tried to open undef directory');

    # Dir no exist 
    ok(
        !Genome::Utility::FileSystem->open_directory('/tmp/no_way_this_exists_for_cryin_out_loud'), 
        'Tried to open a non existing directory'
    );
    
    # Dir is file
    ok(
        !Genome::Utility::FileSystem->open_directory( sprintf('%s/existing_file.txt', _base_test_dir()) ),
        'Try to open a directory, but it\'s a file',
    );

    return 1;
}

sub test1_create_directory : Test(3) {
    my $self = shift;

    my $base_new_dir = sprintf('%s/new', _base_test_dir());
    my $new_dir = sprintf('%s/dir/with/sub/dirs/', $base_new_dir);
    Genome::Utility::FileSystem->create_directory($new_dir);
    ok(-d $new_dir, "Created new dir: $new_dir");
    my $fifo = $new_dir .'/test_pipe';
    `mkfifo $fifo`;
    ok(!Genome::Utility::FileSystem->create_directory($fifo),'failed to create_directory '. $fifo);
    ok(File::Path::rmtree($base_new_dir), "Removed base new dir: $base_new_dir");

    return 1;
}

sub test2_resource_locking : Test(10) {
    my $bogus_id = '-55555';
    my $tmp_dir = File::Temp::tempdir(CLEANUP => 1);
    my $sub_dir = $tmp_dir .'/sub/dir/test';
    ok(! -e $sub_dir,$sub_dir .' does not exist');
    ok(Genome::Utility::FileSystem->create_directory($sub_dir),'create directory');
    ok(-d $sub_dir,$sub_dir .' is a directory');

    ok(Genome::Utility::FileSystem->lock_resource(
                                                  lock_directory => $tmp_dir,
                                                  resource_id => $bogus_id,
                                              ),'lock resource_id '. $bogus_id);
    my $expected_lock_info = $tmp_dir .'/'. $bogus_id .'.lock/info';
    ok(-f $expected_lock_info,'lock info file found '. $expected_lock_info);
    ok(!Genome::Utility::FileSystem->create_directory($expected_lock_info),
       'failed to create_directory '. $expected_lock_info);
    ok(!Genome::Utility::FileSystem->lock_resource(
                                                   lock_directory => $tmp_dir,
                                                   resource_id => $bogus_id,
                                                   max_try => 1,
                                                   block_sleep => 3,
                                               ),
       'failed lock resource_id '. $bogus_id);
    ok(Genome::Utility::FileSystem->unlock_resource(
                                                    lock_directory => $tmp_dir,
                                                    resource_id => $bogus_id,
                                                ), 'unlock resource_id '. $bogus_id);
    ok(Genome::Utility::FileSystem->lock_resource(
                                                  lock_directory => $tmp_dir,
                                                  resource_id => $bogus_id,
                                              ),'lock resource_id '. $bogus_id);
    ok(Genome::Utility::FileSystem->unlock_resource(
                                                    lock_directory => $tmp_dir,
                                                    resource_id => $bogus_id,
                                                ), 'unlock resource_id '. $bogus_id);
}

=pod

=head1 Tests

=head1 Disclaimer

 Copyright (C) 2008 Washington University Genome Sequencing Center

 This script is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY
 or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
 License for more details.

=head1 Author(s)

 Eddie Belter <ebelter@watson.wustl.edu>

=cut

#$HeadURL$
#$Id$
