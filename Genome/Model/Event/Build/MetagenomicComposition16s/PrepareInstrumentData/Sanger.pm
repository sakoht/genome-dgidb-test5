package Genome::Model::Event::Build::MetagenomicComposition16s::PrepareInstrumentData::Sanger;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';

class Genome::Model::Event::Build::MetagenomicComposition16s::PrepareInstrumentData::Sanger {
    is => 'Genome::Model::Event::Build::MetagenomicComposition16s::PrepareInstrumentData',
};

sub execute {
    my $self = shift;

    $self->_dump_and_link_instrument_data
        or return;

    my $amplicon_set = $self->build->amplicon_sets # sanger build only have one
        or return;

    $self->_raw_reads_fasta_and_qual_writer
        or return;

    my $attempted = 0;
    while ( my $amplicon = $amplicon_set->() ) {
        $attempted++;
        $self->_prepare_instrument_data_for_phred_phrap($amplicon)
            or return;
    }

    $self->build->amplicons_attempted($attempted);

    return 1;
}

sub _raw_reads_fasta_and_qual_writer {
    my $self = shift;

    unless ( $self->{_raw_reads_fasta_and_qual_writer} ) {
        $self->{_raw_reads_fasta_and_qual_writer} = $self->build->raw_reads_fasta_and_qual_writer
            or return;
    }

    return $self->{_raw_reads_fasta_and_qual_writer};
}

#< Dumping/Linking Instrument Data >#
sub _dump_and_link_instrument_data {
    my $self = shift;

    unless ( $self->model->sequencing_center eq 'gsc' ) {
        # TODO add logic for other centers...
        return 1;
    }

    my @idas = $self->model->instrument_data_assignments;
    unless ( @idas ) {
        $self->error_message(
            sprintf(
                'No instrument data assigned to model for model (<Name> %s <Id> %s).',
                $self->model->name,
                $self->model->id,
            )
        );
        return;
    }

    for my $ida ( @idas ) {
        # dump
        unless ( $ida->instrument_data->dump_to_file_system ) {
            $self->error_message(
                sprintf(
                    'Error dumping instrument data (%s <Id> %s) assigned to model (%s <Id> %s)',
                    $ida->instrument_data->run_name,
                    $ida->instrument_data->id,
                    $self->model->name,
                    $self->model->id,
                )
            );
            return;
        }
        $ida->first_build_id( $self->build_id );

        # link
        unless ( $self->build->link_instrument_data( $ida->instrument_data ) ) {
            $self->error_message(
                sprintf(
                    'Error linking instrument data (%s <Id> %s) to model (%s <Id> %s)',
                    $ida->instrument_data->run_name,
                    $ida->instrument_data->id,
                    $self->model->name,
                    $self->model->id,
                )
            );
            return;
        }
    }

    return 1;
}

#< Phred, Phred to Fasta >#
sub _prepare_instrument_data_for_phred_phrap {
    my ($self, $amplicon) = @_;

    my $scfs_file = $self->build->create_scfs_file_for_amplicon($amplicon);
    my $phds_file = $self->build->phds_file_for_amplicon($amplicon);
    my $fasta_file = $self->build->reads_fasta_file_for_amplicon($amplicon);
    my $qual_file = $self->build->reads_qual_file_for_amplicon($amplicon);
    
    # Phred
    my $scf2phd = Genome::Model::Tools::PhredPhrap::ScfToPhd->create(
        chromat_dir => $self->build->chromat_dir,
        phd_dir => $self->build->phd_dir,
        phd_file => $phds_file,
        scf_file => $scfs_file,
    );
    unless ( $scf2phd ) {
        $self->error_message("Can't create scf to phd command");
        return;
    }
    unless ( $scf2phd->execute ) {
        $self->error_message("Can't execute scf to phd command");
        return;
    } 
    
    # Phred to Fasta
    my $phd2fasta = Genome::Model::Tools::PhredPhrap::PhdToFasta->create(
        fasta_file => $fasta_file,
        phd_dir => $self->build->phd_dir,
        phd_file => $phds_file,
    );
    unless ( $phd2fasta ) {
        $self->error_message("Can't create phd to fasta command");
        return;
    }
    unless ( $phd2fasta->execute ) {
        $self->error_message("Can't execute phd to fasta command");
        return;
    }
    
    # Write the 'raw' read fastas
    my $reader = $self->build->fasta_and_qual_reader($fasta_file, $qual_file)
        or return;
    while ( my $bioseq = $reader->() ) {
        $self->_raw_reads_fasta_and_qual_writer->($bioseq)
            or return;
    }
    
    return 1;
}

1;

#$HeadURL$
#$Id$
