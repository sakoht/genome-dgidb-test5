#! /gsc/bin/perl

use strict;
use warnings;

use above 'Genome';

require File::Compare;
use Test::More;

use_ok('Genome::Model::Tools::FastQual::Rename::IlluminaToPcap') or die;

# Files
my $dir = '/gsc/var/cache/testsuite/data/Genome-Model-Tools-FastQual';
my $in_fastq = $dir.'/rename.in.fastq';
ok(-s $in_fastq, 'in fastq');
my $example_fastq = $dir.'/rename.example.fastq';
ok(-s $example_fastq, 'example fastq');

my $tmp_dir = File::Temp::tempdir(CLEANUP => 1);
my $out_fastq = $tmp_dir.'/out.fastq';

# Ok
my $renamer = Genome::Model::Tools::FastQual::Rename::IlluminaToPcap->create(
    input  => [ $in_fastq ],
    output => [ $out_fastq ],
);
ok($renamer, 'create renamer');
isa_ok($renamer, 'Genome::Model::Tools::FastQual::Rename::IlluminaToPcap');
ok($renamer->execute, 'execute renamer');
is(File::Compare::compare($example_fastq, $out_fastq), 0, "renamed as expected");

#print "$tmp_dir\n"; <STDIN>;
done_testing();
exit;

=pod

=head1 Tests

=head1 Disclaimer

 Copyright (C) 2010 Washington University Genome Sequencing Center

 This script is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY
 or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
 License for more details.

=head1 Author(s)

 Eddie Belter <ebelter@watson.wustl.edu>

=cut

