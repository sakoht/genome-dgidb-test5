package Genome::InstrumentData::AlignmentSet::Bwa;

use strict;
use warnings;
use File::Basename;

use Genome;

class Genome::InstrumentData::AlignmentSet::Bwa {
    is => 'Genome::InstrumentData::AlignmentSet',
    has_constant => [
        aligner_name => { value => 'bwa', is_param=>1 },
    ],
    has_optional => [
         _bwa_sam_cmd => { is=>'Text' }
    ]
};

sub required_arch_os { 'x86_64' }

sub required_rusage { 
    "-R 'select[model!=Opteron250 && type==LINUX64 && tmp>90000 && mem>10000] span[hosts=1] rusage[tmp=90000, mem=10000]' -M 10000000 -n 4";
}

sub _run_aligner {
    my $self = shift;
    my @input_pathnames = @_;

    my $tmp_dir = $self->temp_scratch_directory;

    # get refseq info
    my $reference_build = $self->reference_build;
    my $ref_basename = File::Basename::fileparse($reference_build->full_consensus_path('fa'));
    my $reference_fasta_path = sprintf("%s/%s", $reference_build->data_directory, $ref_basename);

    # decompose aligner params for each stage of bwa alignment
    my %aligner_params = $self->decomposed_aligner_params;

   
    #### STEP 1: Use "bwa aln" to align each fastq independently to the reference sequence 

    my $bwa_aln_params = (defined $aligner_params{'bwa_aln_params'} ? $aligner_params{'bwa_aln_params'} : "");
    my @sai_intermediate_files;
    my @aln_log_files; 
    foreach my $input (@input_pathnames) {
   
        my ($tmp_base) = fileparse($input); 
        my $tmp_sai_file = $tmp_dir . "/" . $tmp_base . ".sai";
        my $tmp_log_file = $tmp_dir . "/" . $tmp_base . ".bwa.aln.log"; 
        
        my $cmdline = Genome::Model::Tools::Bwa->path_for_bwa_version($self->aligner_version)
            . sprintf( ' aln %s %s %s 1> ',
                $bwa_aln_params, $reference_fasta_path, $input )
            . $tmp_sai_file . ' 2>>'
            . $tmp_log_file;
        
        push @sai_intermediate_files, $tmp_sai_file;
        push @aln_log_files, $tmp_log_file;
        
        Genome::Utility::FileSystem->shellcmd(
            cmd          => $cmdline,
            input_files  => [ $reference_fasta_path, $input ],
            output_files => [ $tmp_sai_file, $tmp_log_file ],
            skip_if_output_is_present => 0,
        );

        unless ($self->_verify_bwa_aln_did_happen(sai_file => $tmp_sai_file,
                        log_file => $tmp_log_file)) {
            $self->error_message("bwa aln did not seem to successfully take place for " . $reference_fasta_path);
            $self->die_and_clean_up($self->error_message);
        }
    }


    #### STEP 2: Use "bwa samse" or "bwa sampe" to perform single-ended or paired alignments, respectively.
    #### Runs once for ALL input files

    my $samxe_logfile       = $tmp_dir . "/bwa.samxe.log"; 
    my $sam_command_line = ""; 
    my @input_files;
    my $sam_file = $self->temp_scratch_directory . "/all_sequences.sam";

    if ( @input_pathnames == 1 ) {
        my $bwa_samse_params = (defined $aligner_params{'bwa_samse_params'} ? $aligner_params{'bwa_samse_params'} : "");
        @input_files = ($sai_intermediate_files[0], $input_pathnames[0]);
    
         $self->_bwa_sam_cmd("bwa samse " . $bwa_samse_params);
         $sam_command_line = Genome::Model::Tools::Bwa->path_for_bwa_version($self->aligner_version)
                . sprintf(
                ' samse %s %s %s %s',
                $bwa_samse_params, $reference_fasta_path,
                $sai_intermediate_files[0],
                $input_pathnames[0]
                )
                . " 2>>"
                . $samxe_logfile;

        die "Failed to process sam command line, error_message is ".$self->error_message unless $self->_filter_samxe_output($sam_command_line, $sam_file);
    
    }
    elsif (@input_pathnames == 2) {
        my $bwa_sampe_params = (defined $aligner_params{'bwa_sampe_params'} ? $aligner_params{'bwa_sampe_params'} : "");
        
        # Ignore where we have a -a already specified
        if ($bwa_sampe_params =~ m/\-a\s*(\d+)/) {
            $self->status_message("Aligner params specify a -a parameter ($1) as upper bound on insert size.");
        } else {
            # come up with an upper bound on insert size.
            my $instrument_data = $self->instrument_data;
            my $sd_above = $instrument_data->sd_above_insert_size;
            my $median_insert = $instrument_data->median_insert_size;
            my $upper_bound_on_insert_size= ($sd_above * 5) + $median_insert;
            if($upper_bound_on_insert_size > 0) {
                $self->status_message("Calculated a valid insert size as $upper_bound_on_insert_size.  This will be used when BWA's internal algorithm can't determine an insert size");
            } else {
                $self->status_message("Unable to calculate a valid insert size to run BWA with. Using 600 (hax)");
                $upper_bound_on_insert_size= 600;
            }

            $bwa_sampe_params .= " -a $upper_bound_on_insert_size";
        }
    
        # paired run
        #my $upper_bound_option     = '-a ' . $self->upper_bound;
        #my $max_occurrences_option = '-o ' . $self->max_occurrences;
        my $paired_options = ""; #$upper_bound_option $max_occurrences_option";
    
        @input_files = (@sai_intermediate_files, @input_pathnames);

        # store the calculated sampe params
        $self->_bwa_sam_cmd("bwa sampe " . $bwa_sampe_params);
        $sam_command_line = Genome::Model::Tools::Bwa->path_for_bwa_version($self->aligner_version)
            . sprintf(
            ' sampe %s %s %s %s',
            $bwa_sampe_params,
            $reference_fasta_path,
            join (' ', @sai_intermediate_files),
            join (' ', @input_pathnames)
            )
            . " 2>>"
            . $samxe_logfile;
    
        die "Failed to process sam command line, error_message is ".$self->error_message unless $self->_filter_samxe_output($sam_command_line, $sam_file);

    } 
    else {
        $self->error_message("Input pathnames shouldn't have more than 2... contents: " . Data::Dumper::Dumper(\@input_pathnames) );
        die $self->error_message;
    }

    unless (-s $sam_file) {
        die "The sam output file $sam_file is zero length; something went wrong.";
    }


    #### STEP 3: Merge log files.
 
    my $log_input_fileset = join " ",  (@aln_log_files, $samxe_logfile);
    my $log_output_file   = $self->temp_staging_directory . "/aligner.log";
    my $concat_log_cmd = sprintf('cat %s >> %s', $log_input_fileset, $log_output_file);

    Genome::Utility::FileSystem->shellcmd(
        cmd          => $concat_log_cmd,
        input_files  => [ @aln_log_files, $samxe_logfile ],
        output_files => [ $log_output_file ],
        skip_if_output_is_present => 0,
        );

    return 1;
}

sub _filter_samxe_output {
    my ($self, $sam_cmd, $sam_file_name) = @_;

    $DB::single = 1;
    my $sam_run_output_fh = IO::File->new( $sam_cmd . "|" );
    $self->status_message("Running $sam_cmd");
    if ( !$sam_run_output_fh ) {
            $self->error_message("Error running $sam_cmd $!");
            return;
    }


    my $sam_map_output_fh = IO::File->new(">>$sam_file_name");
    if ( !$sam_map_output_fh ) {
            $self->error_message("Error opening sam file for writing $!");
            return;
    }
    $self->status_message("Opened $sam_file_name");
    
    while (<$sam_run_output_fh>) {
            #write out the aligned map, excluding the default header- all lines starting with @.
            my $first_char = substr($_,0,1);
                if ($first_char ne '@') {
                $sam_map_output_fh->print($_);
            }
    }
    $sam_map_output_fh->close;
    return 1;
}


sub _verify_bwa_aln_did_happen {
    my $self = shift;
    my %p = @_;

    unless (-e $p{sai_file} && -s $p{sai_file}) {
        $self->error_message("Expected SAI file is $p{sai_file} nonexistent or zero length.");
        return;
    }
    
    unless ($self->_inspect_log_file(log_file=>$p{log_file},
                                     log_regex=>'(\d+) sequences have been processed')) {
        
        $self->error_message("Expected to see 'X sequences have been processed' in the log file where 'X' must be a nonzero number.");
        return 0;
    }
    
    return 1;
}

sub _inspect_log_file {
    my $self = shift;
    my %p = @_;

    my $aligner_output_fh = IO::File->new($p{log_file});
    unless ($aligner_output_fh) {
        $self->error_message("Can't open expected log file to verify completion " . $p{log_file} . "$!"
        );
        return;
    }
    
    my $check_nonzero = 0;
    
    my $log_regex = $p{log_regex};
    if ($log_regex =~ m/\(\\d\+\)/) {
        
        $check_nonzero = 1;
    }

    while (<$aligner_output_fh>) {
        if (m/$log_regex/) {
            $aligner_output_fh->close();
            if ( !$check_nonzero || $1 > 0 ) {
                return 1;
            }
            return;
        }
    }

    return;
}

sub decomposed_aligner_params {
    my $self = shift;
    my $params = $self->aligner_params || ":::";
    
    my @spar = split /\:/, $params;
    
    
    return ('bwa_aln_params' => $spar[0], 'bwa_samse_params' => $spar[1], 'bwa_sampe_params' => $spar[2]);
}

sub aligner_params_for_sam_header {
    my $self = shift;
    
    my %params = $self->decomposed_aligner_params;
    my $aln_params = $params{bwa_aln_params} || "";
    
    my $sam_cmd = $self->_bwa_sam_cmd || "";

    return "bwa aln $aln_params; $sam_cmd ";
}
