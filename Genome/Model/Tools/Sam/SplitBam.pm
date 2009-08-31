package Genome::Model::Tools::Sam::SplitBam;

use strict;
use warnings;

use Genome;
use File::Basename;
use File::Temp;
use POSIX qw(mkfifo);

class Genome::Model::Tools::Sam::SplitBam {
    is => 'Genome::Model::Tools::Sam',
    has_input => [
        bam_file => {
            is => 'Text',
        },
        output_directory => {
            is => 'Text',
        },
        reference_index => {
            is => 'Text',
            doc => 'The reference fasta index for creating sub-bams',
            default_value => '/gscmnt/839/info/medseq/reference_sequences/NCBI-human-build36/all_sequences.fa.fai',
        },
        size => {
            is => 'Integer',
            doc => 'The number of alignments to include in each bam file',
            default_value => '1000000',
        },
    ],
    has_output => [
        sub_bam_files => {
            is => 'Array',
            doc => 'The sub-bam files created during the split',
            is_optional => 1,
        },
    ]
};

sub execute {
    my $self = shift;

    unless (-e $self->bam_file) {
        $self->error_message('Failed to find bam file: '. $self->bam_file .":  $!");
        die($self->error_message);
    }

    unless (-d $self->output_directory) {
        unless (Genome::Utility::FileSystem->create_directory($self->output_directory)) {
            $self->error_message('Failed to create output directory '. $self->output_directory .":  $!");
            die($self->error_message);
        }
    }

    my @bam_suffix = qw/bam/;
    my @sam_suffix = qw/sam/;
    my ($basename,$dirname,$suffix) = File::Basename::fileparse($self->bam_file,@bam_suffix);
    $basename =~ s/\.$//;

    # This should be a named pipe
    my $whole_tmp_sam = Genome::Utility::FileSystem->create_temp_file_path($basename .'.sam');
    mkfifo($whole_tmp_sam,02700) || die('Failed to make named pipe '. $whole_tmp_sam);
    while (!-e $whole_tmp_sam) {
        sleep 1;
    }
    
    my $sam_view_cmd = $self->samtools_path .' view -o '. $whole_tmp_sam .' '. $self->bam_file .' &' ;
    Genome::Utility::FileSystem->shellcmd(
        cmd => $sam_view_cmd,
    );

    my $whole_sam_fh = IO::File->new($whole_tmp_sam,'r');
    my $file_counter = 1;
    my @bam_files;
    while ($whole_sam_fh->opened) {
        my ($tmp_sam_fh,$tmp_sam_file) = Genome::Utility::FileSystem->create_temp_file($basename .'_'. $file_counter .'.sam');
        for (my $i = 0; $i < $self->size; $i++) {
            if (my $sam = $whole_sam_fh->getline) {
                $tmp_sam_fh->print($sam);
            } else {
                $whole_sam_fh->close;
            }
        }
        $tmp_sam_fh->close;
        $file_counter++;
        my ($sam_basename,$sam_dirname,$sam_suffix) = File::Basename::fileparse($tmp_sam_file,@sam_suffix);
        $sam_basename =~ s/\.$//;
        my $bam_file = $self->output_directory .'/'. $sam_basename .'.bam';
        unless ( Genome::Model::Tools::Sam::SamToBam->execute(
            sam_file => $tmp_sam_file,
            bam_file => $bam_file,
            ref_list => $self->reference_index,
            use_version => $self->use_version,
            index_bam => 0,
        ) ) {
            $self->error_message('Failed to convert sam file '. $tmp_sam_file .' to bam file '. $bam_file);
            die($self->error_message);
        }
        unlink($tmp_sam_file);
        push @bam_files, $bam_file;
    }
    $self->sub_bam_files(\@bam_files);
    return 1;
}
