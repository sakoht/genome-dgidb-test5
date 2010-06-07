package Genome::InstrumentData::AlignmentResult::Shrimp2;

use strict;
use warnings;
use File::Basename;

use Genome;

class Genome::InstrumentData::AlignmentResult::Shrimp2 {
    is => 'Genome::InstrumentData::AlignmentResult',
    has_constant => [
        aligner_name => { value => 'shrimp2', is_param=>1 },
    ],
    has_transient => [
        static_params => { is => 'String', is_optional => 1 }
    ]
};

sub required_arch_os { 'x86_64' }

sub required_rusage { 
    "-R 'select[model!=Opteron250 && type==LINUX64 && tmp>90000 && mem>24000] rusage[tmp=90000, mem=24000]' -M 24000000";
}

sub _run_aligner {
    my $self = shift;

    my $aligner_params = $self->aligner_params || '';
    
    # collect filepaths
    my $shrimp_path = Genome::Model::Tools::Shrimp2->path_for_shrimp2_version($self->aligner_version);
    my $ref_index = $self->reference_build->data_directory . '/all_sequences.fa';
    my $output_file = $self->temp_scratch_directory . "/all_sequences.sam";
    my $log_file = $self->temp_staging_directory . "/aligner.log";
    my @inputs = map { $self->fastq_to_fasta($_) } @_;
    my $input_path = $inputs[0];

    # special things for paired data
    $self->static_params('-E');
    if ( @inputs == 2 ) {
        unless ( $aligner_params =~ /-p/ ){
            my ($lower,$upper) = $self->_derive_insert_size_bounds;
            $self->static_params($self->static_params . " -p opp-in -I $lower,$upper");
        }
        $input_path = $self->merge_pairs(@inputs);
    }

    # construct command and run it
    my $static_params = $self->static_params;
    my $cmd = "$shrimp_path $aligner_params $static_params $input_path $ref_index 2>>$log_file >>$output_file";

    Genome::Utility::FileSystem->shellcmd(
        cmd          => $cmd,
        input_files  => [ $ref_index, $input_path ],
        output_files => [ $output_file, $log_file ],
        skip_if_output_is_present => 0
    );

    unless (-s $output_file){
        $self->error_message('The sam output file is missing or empty.');
        return 0;
    }
    $self->status_message('SHRiMP2 alignment finished.');
    return 1;
}

sub aligner_params_for_sam_header {
    my $self = shift;
    return 'shrimp2 ' . $self->aligner_params . ' ' . $self->static_params;
}

sub fastq_to_fasta {
    my $self = shift;
    my $input = shift;
    my $output = $input . ".fa";
    $self->status_message("Converting $input (FastQ) to $output (FastA).");
    my $fastq_fh = IO::File->new($input);
    my $fasta_fh = IO::File->new(">$output");
    my $line_type;
    while (<$fastq_fh>){
        $line_type = $. % 4;
        if ($line_type == 1) {
            $fasta_fh->print(">",substr($_,1));
        } elsif ($line_type == 2) {
            $fasta_fh->print($_);
        }
    }
    $fasta_fh->close();
    $fastq_fh->close();
    return $output;
}

# note: this may be completely wrong. fix later!
sub _derive_insert_size_bounds {
    my $self = shift;
    my $median = $self->instrument_data->median_insert_size;
    my $stddev = $self->instrument_data->sd_above_insert_size;
    #my $readlen = $self->instrument_data->read_length;
    my $upper = $median + $stddev*5;
    my $lower = $median - $stddev*5;
    if ( $upper <= 0 ) {
        $self->status_message("Calculated upper bound on insert size is invalid ($upper), defaulting to 600");
        $upper = 600;
    }
    if ( not $median || $lower < 0 || $lower > $upper ) {
        # alternative default = read_length + rev_read_length
        $self->status_message("Calculated lower bound on insert size is invalid ($lower), defaulting to 50");
        $lower = 50;
    }
    return ($lower,$upper);
}

sub merge_pairs {
    my $self = shift;
    my @inputs = @_;
    my $merged = $inputs[0];
    $merged =~ s/\.fa/_merged\.fa/;
    
    $self->status_message("Interleaving $inputs[0] and $inputs[1] into one file.");
    my ($infh1,$infh2) = map { IO::File->new($_) } @inputs;
    my $merged_fh = IO::File->new(">$merged");
    my $line_type;
    while (<$infh1>){
        $line_type = $. % 2;
        if ($line_type == 1) {
            $merged_fh->print($_);
        } elsif ($line_type == 0) {
            $merged_fh->print($_,scalar(<$infh2>),scalar(<$infh2>));
        }
    }
    $infh1->close();
    $infh2->close();
    $merged_fh->close();
    return $merged;
}
