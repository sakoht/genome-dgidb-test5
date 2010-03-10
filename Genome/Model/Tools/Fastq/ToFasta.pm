package Genome::Model::Tools::Fastq::ToFasta;

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Fastq::ToFasta {
    is => 'Genome::Model::Tools::Fastq',
    has_input => [
            fasta_file => {
                           is => 'Text',
                           doc => 'the output fasta format sequence file',
                       },
            quality_file => {
                             is => 'Text',
                             is_optional => 1,
                             doc => 'the output fasta format quality file',
                         },
        ],
};

sub create {
    my $class = shift;
    
    my $self = $class->SUPER::create(@_);

    return $self;
}

sub execute {
    my $self = shift;

    #unless ($self->quality_file) {
        $self->fastQ2A;
    #}# else {
     #   $self->bio_convert;
    #}
    return 1;
}

sub fastQ2A {
    my $self = shift;
    #This is bad, what if the first base has a quality of '@'....
    local $/ = "\n@";
    my $in_fh = Genome::Utility::FileSystem->open_file_for_reading($self->fastq_file);
    my $out_fh = Genome::Utility::FileSystem->open_file_for_writing($self->fasta_file);
    my $qual_fh;
    if ($self->quality_file) {
        $qual_fh = Genome::Utility::FileSystem->open_file_for_writing($self->quality_file);
    }
    while (my $line = $in_fh->getline) {
        # @HWI-EAS75:1:2:0:345#0/1
        # NCCGCGAGATCGGAAGAGCGGTTCAGCAGGAATGC
        # +HWI-EAS75:1:2:0:345#0/1
        # ENUUUXVUVUUTPTXTSTTQQQVVTTPQVVVVUTQ
        chomp($line);
        if ($line =~ /^\@/) { $line =~ s/\@//g }  # first-in
        my ($id1, $nt, $id2, $qual) = split (/\n/, $line);
        if ($id1 && $nt) {
            print $out_fh '>' . $id1 . "\n";
            print $out_fh $nt . "\n";
        }
        if ($qual_fh && $id1 && $qual) {
            print $qual_fh '>' . $id1 . "\n";
            print $qual_fh $qual . "\n";
        }
    }
    $in_fh->close;
    local $/ = "\n";
    return 1;
}

sub bio_convert {
    my $self = shift;
    # TODO: may need a flag to perform quality conversion as well?
    $self->error_message('For quality too, please implement bio_convert method in '. __PACKAGE__);
    die $self->error_message;
}
