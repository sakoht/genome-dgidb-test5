package Genome::Model::Tools::Fastq;

use strict;
use warnings;

use Genome;
use Bio::SeqIO;

class Genome::Model::Tools::Fastq {
    is => 'Command',
    has => [
        fastq_file => {
            type        => 'Text',
            is_optional => 0,
            doc         => 'FASTQ file that contains both sequences and quality values',
        },
    ],
};

sub help_brief {
    "tools for working with FASTQ files"
}


sub help_detail {
    "Tools to work with fastq format files";
}


sub create { 
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    $self->{_cwd} = Cwd::getcwd();
    $self->fastq_file(Cwd::abs_path($self->fastq_file));
    my ($basename, $directory) = File::Basename::fileparse( $self->fastq_file );
    
    $self->{_fastq_basename}  = $basename;
    $self->{_fastq_directory} = $directory;

    return $self;
}


sub DESTROY {
    my $self = shift;
    $self->chdir_cwd;    
    return 1;
}


sub cwd {
    return shift->{_cwd};
}


sub chdir_cwd {
    my $self = shift;

    unless (chdir $self->cwd) {
        $self->error_message(sprintf('Can\'t access cwd (%s)', $self->cwd));
        return;
    }
    return 1;
}


sub fastq_basename {
    return shift->{_fastq_basename};
}


sub fastq_directory {
    return shift->{_fastq_directory};
}


sub get_fastq_reader {
    return _get_bioseq_reader(@_, 'fastq');
}


sub _get_bioseq_reader {
    return _get_bioseq(@_, '<');
}


sub get_fastq_writer {
    return _get_bioseq_writer(@_, 'fastq');
}


sub _get_bioseq_writer {
    return _get_bioseq(@_, '>');
}


sub _get_bioseq {
    my ($self, $file, $format, $rw) = @_;

    return Bio::SeqIO->new(
        -file   => $rw.' '.$file,
        -format => $format,
    );
}
    

1;


