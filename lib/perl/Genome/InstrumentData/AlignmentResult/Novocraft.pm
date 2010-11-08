package Genome::InstrumentData::AlignmentResult::Novocraft;

use strict;
use warnings;
use File::Basename;

use Genome;

class Genome::InstrumentData::AlignmentResult::Novocraft {
    is => 'Genome::InstrumentData::AlignmentResult',
    has_constant => [
        aligner_name => { value => 'Novocraft', is_param=>1 },
    ]
};

sub required_arch_os { 'x86_64' }

# fill me in here with what compute resources you need.
sub required_rusage { 
    "-R 'select[model!=Opteron250 && type==LINUX64 && tmp>90000 && mem>10000] span[hosts=1] rusage[tmp=90000, mem=10000]' -M 10000000 -n 1";
}


sub _run_aligner {
    my $self = shift;
    my @input_pathnames = @_;

    # get refseq info
    my $reference_build = $self->reference_build;
    my $reference_novocraft_index_path = $reference_build->full_consensus_path('novocraft');
    
    # check index file exists and is non-zero sized.
    unless (-s $reference_novocraft_index_path) {
        $self->error_message("Index file not found or empty at $reference_novocraft_index_path");
        die; 
    };

    my $aligner_params = $self->aligner_params;

    my $path_to_novoalign = Genome::Model::Tools::Novocraft->path_for_novocraft_version($self->aligner_version);

    my $output_file = $self->temp_scratch_directory . "/all_sequences.sam";
    my $novocraft_output = $self->temp_scratch_directory . "/all_sequences_novocraft_raw.sam";
    my $cleaned_with_headers = $self->temp_scratch_directory . "/all_sequences_with_headers.sam";
    my $log_file = $self->temp_staging_directory . "/aligner.log";

    if ( @input_pathnames > 2 ) {
        $self->error_message("Input pathnames shouldn't have more than 2...: " . Data::Dumper::Dumper(\@input_pathnames) );
        die $self->error_message;
    }
    
    # Format command
    $DB::single = 1;
    my $cmdline = sprintf('%s %s -d %s -f %s -o SAM 1>> %s 2>> %s',
        $path_to_novoalign,
        $aligner_params,
        $reference_novocraft_index_path,
        join(' ', @input_pathnames),
        $novocraft_output,
        $log_file
    );
    $DB::single = 1;
    
    # Execute alignment command
    Genome::Utility::FileSystem->shellcmd(
        cmd                         => $cmdline,
        input_files                 => [@input_pathnames],
        output_files                => [$novocraft_output],
        skip_if_output_is_present   => 0,
    );
    
    $DB::single = 1;
    # Run raw output through SamToBam in order to fix mates.
    my $intermediate_bam_file = $self->temp_scratch_directory . "/all_sequences_with_header.bam";
    my $sam_to_bam_object = Genome::Model::Tools::Sam::SamToBam->create(
        sam_file    => $novocraft_output,
        ref_list    => $self->reference_build->data_directory . "/all_sequences.fa.fai",
        bam_file    => $intermediate_bam_file,
        fix_mate    => 1
    );
    
    $sam_to_bam_object->execute;

    # Convert Bam from fix mates to Sam
    Genome::Model::Tools::Sam::BamToSam->execute(
        bam_file    => $intermediate_bam_file,
        sam_file    => $cleaned_with_headers
    );
    
    $self->_strip_header($cleaned_with_headers, $output_file);

    return 1;
}

sub _strip_header {
    my ($self, $novocraft_output, $output_file) = @_;
    my $novocraft_output_fh = IO::File->new( $novocraft_output );
    
    unless ( $novocraft_output_fh ) {
        $self->error_message("Error opening novocraft output file: $novocraft_output for writing!");
        die;
    }
    $DB::single = 1;
    my $output_file_fh = IO::File->new(">>$output_file");
    unless ( $output_file_fh ) {
            $self->error_message("Error opening output sam file: $output_file for writing!");
            die;
    }
    
    $self->status_message("Removing Novocraft generated header from SAM file.");
    $DB::single = 1;
    while (<$novocraft_output_fh>) {
            #write out the aligned map, excluding the default header- all lines starting with @.
            my $first_char = substr($_,0,1);
                if ($first_char ne '@') {
                $output_file_fh->print($_);
            }
    }
    $novocraft_output_fh->close;
    $output_file_fh->close;
    return 1;
}

sub aligner_params_for_sam_header {
    my $self = shift;

    my $aligner_params = $self->aligner_params || '';
    return "novocraft " . $aligner_params;
    # for bwa this looks like "bwa aln -t4; bwa samse 12345'
}

sub fillmd_for_sam { return 0; }

sub _check_read_count { return 1; }
