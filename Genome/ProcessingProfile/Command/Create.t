#!/gsc/bin/perl

use strict;
use warnings;

use above "Genome";

use Data::Dumper;
use Test::More tests => 43;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

BEGIN {
    use_ok('Genome::ProcessingProfile::Command::Create');
}

my %pp_params = (
    'Genome::ProcessingProfile::Command::Create::MetaGenomicComposition' => {
        name => 'test_meta_genomic_composition',
        sequencing_platform => 'sanger',
        assembler => 'phredphrap',
        sequencing_center => 'gsc',
        assembly_size => 12345,
        # FIXME once this is fixed
        #sense_primer_sequences => [qw/ AGAGTTTGATCCTGGCTCAG /],
        #anti_sense_primer_sequences => [qw/ GACGGGCGGTGWGTRCA CCGTCAATTCCTTTRAGTTT /],
        ribosomal_subunit => 16,
        subject_location => 'ocean',
    },
    'Genome::ProcessingProfile::Command::Create::ReferenceAlignment' => {
        name => 'test_reference_alignment',
        sequencing_platform => 'solexa',
        read_aligner_name => 'maq0_6_8',
        reference_sequence_name => 'refseq-for-test',
        dna_type => 'genomic dna',
    },
    'Genome::ProcessingProfile::Command::Create::Assembly' => {
        name => 'test_assembly',
        sequencing_platform => '454',
        assembler_name => 'newbler',
        assembler_params => 'test',
    },
    'Genome::ProcessingProfile::Command::Create::MicroArrayAffymetrix' => {
        name => 'test_micro_array_affymetrix',
    },
    'Genome::ProcessingProfile::Command::Create::MicroArrayIllumina' => {
        name => 'test_micro_array_illumina',
    },
);

# create the processing profile
# 2 tests each
for my $class (keys %pp_params) {
    my $create_command = $class->create($pp_params{$class});
    isa_ok($create_command,$class);
    ok($create_command->execute,'execute '. $class->command_name);
}

# try to create an exact duplicate pp
# 4 tests each
for my $class (keys %pp_params) {
    my $create_command = $class->create($pp_params{$class});
    isa_ok($create_command,$class);
    $create_command->dump_error_messages(0);
    $create_command->queue_error_messages(1);

    ok(!$create_command->execute,'exact duplicate failed to execute '. $class->command_name);

    my @error_messages = $create_command->error_messages();
    ok(scalar(@error_messages), 'Failed execution did emit some error_messages');
    is($error_messages[0], 'Processing profile (above) with same name already exists', 'Error complains about duplicate name');
}

# try to create a pp with the same params
# 4 tests each
for my $class (keys %pp_params) {
    # Skip classes that don't have params
    next unless $class->get_class_object->get_property_objects;

    # Create 'new' name
    $pp_params{$class}->{name} .= '_duplicate';
    my $create_command = $class->create($pp_params{$class});
    isa_ok($create_command,$class);

    $create_command->dump_error_messages(0);
    $create_command->queue_error_messages(1);
    ok(!$create_command->execute,'duplicate params failed to execute '. $class->command_name);

    my @error_messages = $create_command->error_messages();
    ok(scalar(@error_messages), 'Failed execution did emit some error_messages');
    is($error_messages[0], 'Identical processing profile (above) already exists', 'Error messages complains about identical params');
}

exit;

#$HeadURL$
#$Id$
