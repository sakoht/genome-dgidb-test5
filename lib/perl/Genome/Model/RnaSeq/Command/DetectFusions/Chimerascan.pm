package Genome::Model::RnaSeq::Command::DetectFusions::Chimerascan;

use strict;
use warnings;

use Genome;

class Genome::Model::RnaSeq::Command::DetectFusions::Chimerascan {
    is => 'Genome::Model::RnaSeq::Command::DetectFusions::Base',
    doc => 'run the chimerascan transcript fusion detector',
};

sub help_synopsis {
    return <<EOS
 genome model rna-seq detect-fusions chimerascan index_dir/ f1.fastq f2.fast2 output_dir/

 genome model rna-seq detect-fusions chimerascan index_dir/ f1.fastq f2.fast2 output_dir/ --use-version 1.2.3 --params "-a -b -c"
EOS
}

sub help_detail {
    return <<EOS
Run the chimerascan gene fusion detector.

It is used by the RNASeq pipeline to perform fusion detection when the fusion detection strategy is set to something like:
 'chimerascan 1.2.3'

EOS
}

sub execute {
    my $self = shift;

    unless($self->_fetch_result('get_or_create')){
        die("Unable to create a software result for Chimerascan");
    }

    return 1;
}

sub shortcut {
    my $self = shift;
    return $self->_fetch_result('get_with_lock');
}

sub _fetch_result {
    my $self = shift;
    my $method = shift;

    my $result = Genome::Model::RnaSeq::DetectFusionsResult::ChimerascanResult->$method(
            test_name => $ENV{GENOME_SOFTWARE_RESULT_TEST_NAME} || undef,
            version => $self->version,
            alignment_result => $self->build->alignment_result,
            detector_params => $self->detector_params,
    );

    if ($result){
        $self->_link_build_to_result($result);
        return 1;
    }

    return 0;
}

1;
