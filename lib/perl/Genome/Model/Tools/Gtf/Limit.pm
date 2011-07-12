package Genome::Model::Tools::Gtf::Limit;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Gtf::Limit {
    is => ['Genome::Model::Tools::Gtf::Base',],
    has => [
        id_type => {
            is => 'Text',
            default_value => 'transcript_id',
            valid_values => ['gene_id', 'transcript_id'],
            is_optional => 1,
        },
        ids => {
            doc => 'An array ref of ids if used through an API or an fof of ids',
        },
        output_gtf_file => {
            is => 'Text',
            doc => 'The output gtf format file.',
        },
    ],
};

sub execute {
    my $self = shift;

    my $gtf_reader = Genome::Utility::IO::GffReader->create(
        input => $self->input_gtf_file,
    );
    unless ($gtf_reader) {
        die('Failed to create gtf reader for file: '. $self->input_gtf_file);
    }
    my $gtf_writer = Genome::Utility::IO::SeparatedValueWriter->create(
        output => $self->output_gtf_file,
        headers => $gtf_reader->headers,
        separator => $gtf_reader->separator,
        print_headers => 0,
    );
    unless ($gtf_writer) {
        die('Failed to create gtf writer for file: '. $self->output_gtf_file);
    }

    my $ids = $self->ids;
    my %ids;
    unless (ref($ids) eq 'ARRAY') {
        my $ids_fh = IO::File->new($ids,'r');
        unless ($ids_fh) {
            die('Failed to open ids file: '. $ids);
        }
        while (my $line = $ids_fh->getline) {
            unless ($line =~ /^(\S+)$/) {
                die('Malformed line: '. $line);
            }
            $ids{$1} = 1;
        }
        $ids_fh->close;
    } else {
        for my $id (@{$ids}) {
            $ids{$id} = 1;
        }
    }
    while (my $data = $gtf_reader->next_with_attributes_hash_ref) {
        my $attributes = delete($data->{attributes_hash_ref});
        if ($ids{$attributes->{$self->id_type}}) {
            $gtf_writer->write_one($data);
        }
    }

    return 1;
}

1;
