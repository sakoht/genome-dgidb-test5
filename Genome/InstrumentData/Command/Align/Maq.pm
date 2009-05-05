package Genome::InstrumentData::Command::Align::Maq;

use strict;
use warnings;

use Genome;

class Genome::InstrumentData::Command::Align::Maq {
    is => ['Genome::InstrumentData::Command::Align'],
    has_constant => [
        aligner_name                    => { value => 'maq' },
    ],
    doc => 'align instrument data using maq (see http://maq.sourceforge.net)',
};

sub help_synopsis {
return <<EOS
genome instrument-data align maq -r NCBI-human-build36 -i 2761701954

genome instrument-data align maq -r NCBI-human-build36 -i 2761701954 -v 0.6.5

genome instrument-data align maq --reference-name NCBI-human-build36 --instrument-data-id 2761701954 --version 0.6.5

genome instrument-data align maq -i 2761701954 -v 0.6.5
EOS
}

sub help_detail {
return <<EOS
Launch the maq aligner in a standard way and produce results ready for the genome modeling pipeline.

See http://maq.sourceforge.net.
EOS
}

sub run_aligner {
    my $self = shift;
    my %p = @_;

    my $alignment = delete $p{alignment};

    # the rest of these will probably be alignment attributes/methods at some point,
    # and this logic will itself be an alignmen object method too.
    my $alignment_directory = delete $p{output_directory};
    my $reference_build = delete $p{reference_build};
    my $adaptor_file = delete $p{adaptor_file};
    my $aligner_params = delete $p{aligner_params};
    my $is_paired_end = delete $p{is_paired_end};
    my $upper_bound_on_insert_size = delete $p{upper_bound_on_insert_size};

    if (%p) {
        die("Unknown params: " . join(" ",%p) . "\n");
    }

    # we resolve these first, since we might just print the paths we work with then exit
    my @input_pathnames = $alignment->sanger_bfq_filenames;
    $self->status_message("SANGER BFQ PATHS: @input_pathnames\n");

    # prepare the refseq
    my $ref_seq_file =  $reference_build->full_consensus_path('bfa');
    unless ($ref_seq_file && -e $ref_seq_file) {
        $self->error_message("Reference build full consensus path '$ref_seq_file' does not exist.");
        die($self->error_message);
    }
    $self->status_message("REFSEQ PATH: $ref_seq_file\n");

    # input/output files
    my $alignment_file = $alignment_directory .'/all_sequences.map';


    # RESOLVE A STRING OF ALIGNMENT PARAMETERS
    if ($is_paired_end) {
        $aligner_params .= ' -a '. $upper_bound_on_insert_size;
    }

    # TODO: this doesn't really work, so leave it out
    if ($adaptor_file) {
        $aligner_params .= ' -d '. $adaptor_file;
    }
    else {
        Carp::confess("No adaptor file?");
    }

    # prevent randomness!  seed the generator based on the flow cell not the clock
    my $seed = 0; 
    for my $c (split(//,$alignment->instrument_data->flow_cell_id || $alignment->instrument_data_id)) {
        $seed += ord($c)
    }
    $seed = $seed % 65536;
    $self->status_message("Seed for maq's random number generator is $seed.");
    $aligner_params .= " -s $seed ";

    # NOT SURE IF THIS IS USED BUT COULD BE IMPLEMENTED
    #if ( defined($self->duplicate_mismatch_file) ) {
    #    $duplicate_mismatch_option = '-H '.$self->duplicate_mismatch_file;
    #}

    my $files_to_align = join(' ',@input_pathnames);
    my $cmdline = Genome::Model::Tools::Maq->path_for_maq_version($self->version)
        . sprintf(' map %s -u %s %s %s %s > ',
                  $aligner_params,
                  $alignment->unaligned_reads_list_path,
                  $alignment_file,
                  $ref_seq_file,
                  $files_to_align)
            . $alignment->aligner_output_file_path . ' 2>&1';
    my @input_files = ($ref_seq_file, @input_pathnames);
    if ($adaptor_file) {
        push @input_files, $adaptor_file;
    }
    my @output_files = ($alignment_file, $alignment->unaligned_reads_list_path, $alignment->aligner_output_file_path);
    Genome::Utility::FileSystem->shellcmd(
                                          cmd                         => $cmdline,
                                          input_files                 => \@input_files,
                                          output_files                => \@output_files,
                                          skip_if_output_is_present   => 1,
                                      );

    unless ($alignment->verify_aligner_successful_completion($alignment->aligner_output_file_path)) {
        $self->error_message('Failed to verify maq successful completion from output file '. $alignment->aligner_output_file_path);
        die($self->error_message);
    }

    # in some cases maq will "work" but not make an unaligned reads file
    # this happens when all reads are filtered out
    # make an empty file to represent our zero-item list of unaligned reads
    unless (-e $alignment->unaligned_reads_list_path) {
        if (my $fh = IO::File->new(">".$alignment->unaligned_reads_list_path)) {
            $self->status_message("Made empty unaligned reads file since that file is was not generated by maq.");
        } else {
            $self->error_message("Failed to make empty unaligned reads file!: $!");
        }
    }

    # make a sanitized version of the aligner output for comparisons
    my $output = $self->open_file_for_reading($alignment->aligner_output_file_path);
    my $clean = $self->open_file_for_writing($alignment->aligner_output_file_path . '.sanitized');
    while (my $row = $output->getline) {
        $row =~ s/\% processed in [\d\.]+/\% processed in N/;
        $row =~ s/CPU time: ([\d\.]+)/CPU time: N/;
        $clean->print($row);
    }
    $output->close;
    $clean->close;

    # TODO: is this used anymore?  It's a hack left around from AML1
    my $cmd = '/gscmnt/sata114/info/medseq/pkg/maq/branches/lh3/maq-xp/maq-xp pileup -t '. $alignment->aligner_output_file_path .' 2>&1';
    my $line = `$cmd`;
    my ($evenness)=($line=~/(\S+)\%$/);
    IO::File->new(">$alignment_directory/evenness")->print($evenness);
    $DB::single = $DB::stopper;

    my $errors;
    my @found = $alignment->alignment_file_paths_for_subsequence_name('all_sequences');
    unless (@found) {
        $self->error_message("Failed to find map file for all_sequences!");
        $errors++;
    }
    if ($errors) {
        my @files = glob($alignment_directory . '/*');
        $self->error_message("Files in dir are:\n\t" . join("\n\t",@files) . "\n");
        die('Failed to find map files after alignment');
    }

    return 1;
}

sub process_low_quality_alignments {
    my $self = shift;

    my $alignment = $self->_alignment;

    my $unaligned_reads_file = $alignment->unaligned_reads_list_path;
    my @unaligned_reads_files = $alignment->unaligned_reads_list_paths;

    my @paths;

    my $result;
    if (-s $unaligned_reads_file . '.fastq' && -s $unaligned_reads_file) {
        $self->status_message("SHORTCUTTING: ALREADY FOUND MY INPUT AND OUTPUT TO BE NONZERO");
        return 1;
    }
    elsif (-s $unaligned_reads_file) {
        if ($self->_alignment->instrument_data->is_paired_end && !$self->force_fragment) {
            $result = Genome::Model::Tools::Maq::UnalignedDataToFastq->execute(
                in => $unaligned_reads_file, 
                fastq => $unaligned_reads_file . '.1.fastq',
                reverse_fastq => $unaligned_reads_file . '.2.fastq'
            );
        }
        else {
            $result = Genome::Model::Tools::Maq::UnalignedDataToFastq->execute(
                in => $unaligned_reads_file, 
                fastq => $unaligned_reads_file . '.fastq'
            );
        }
        unless ($result) {die "Failed Genome::Model::Tools::Maq::UnalignedDataToFastq for $unaligned_reads_file";}
    }
    else {
        foreach my $unaligned_reads_files_entry (@unaligned_reads_files){
            if ($self->_alignment->instrument_data->is_paired_end && !$self->force_fragment) {
                $result = Genome::Model::Tools::Maq::UnalignedDataToFastq->execute(
                    in => $unaligned_reads_files_entry, 
                    fastq => $unaligned_reads_files_entry . '.1.fastq',
                    reverse_fastq => $unaligned_reads_files_entry . '.2.fastq'
                );
            }
            else {
                $result = Genome::Model::Tools::Maq::UnalignedDataToFastq->execute(
                    in => $unaligned_reads_files_entry, 
                    fastq => $unaligned_reads_files_entry . '.fastq'
                );
            }
            unless ($result) {die "Failed Genome::Model::Tools::Maq::UnalignedDataToFastq for $unaligned_reads_files_entry";}
        }
    }

    unless (-s $unaligned_reads_file || @unaligned_reads_files) {
        $self->error_message("Could not find any unaligned reads files.");
        return;
    }

    return 1;
}

1;

