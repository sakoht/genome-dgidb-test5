use strict;
use warnings;

use above "MGAP";
use Workflow;

use Test::More tests => 7;

BEGIN {
    use_ok('MGAP::Command');
    use_ok('MGAP::Command::GetFastaFiles');
}

my $command = MGAP::Command::GetFastaFiles->create(
                                                   'dev'        => 1,
                                                   'seq_set_id' => 43,
                                                  );

isa_ok($command, 'MGAP::Command::GetFastaFiles');

ok($command->execute());
my @files = @{$command->fasta_files()};

ok(scalar(@files) == 1263);
ok(unlink(@files) == 1263);

is($BAP::DB::DBI::db_env, 'dev');
