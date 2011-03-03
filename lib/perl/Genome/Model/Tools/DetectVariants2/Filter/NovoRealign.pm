#ReAlign BreakDancer SV supporting reads using novoalign and produce a bam file
package Genome::Model::Tools::DetectVariants2::Filter::NovoRealign;

use strict;
use warnings;
use Genome;
use File::Copy;
use File::Basename;


#my %opts = (
#	    n=>"/gscuser/kchen/bin/novoalign-2.05.13",
#	    i=>"/gscuser/kchen/sata114/kchen/Hs_build36/all_fragments/Hs36_rDNA.fa.k14.s3.ndx",
#	    t=>"/gscuser/kchen/1000genomes/analysis/scripts/novo2sam.pl",
#	    f=>"SLX"
#	   );
#getopts('n:i:f:t:',\%opts);
#die("
#Usage:   novoRealign.pl <breakdancer configure file>\n
#Options:
#         -n STRING  Path to novoalign executable
#         -i STRING  Path to novoalign reference sequence index
#         -t STRING  Path to novo2sam.pl
#         -f STRING  Specify platform [$opts{f}]
#\n"
#) unless (@ARGV);


class Genome::Model::Tools::DetectVariants2::Filter::NovoRealign {
    is  => 'Genome::Model::Tools::DetectVariants2::Filter',
    has_optional => [
        config_file => {
            calculate_from => 'detector_directory',
            calculate => q{ return $detector_directory.'/breakdancer_config';},
            doc  => 'breakdancer config file',
        },
        pass_staging_output => {
            is => 'FilePath',
            calculate_from => '_temp_staging_directory',
            calculate => q{ return $_temp_staging_directory . '/svs.hq'; },
        },
        fail_staging_output => {
            is => 'FilePath',
            calculate_from => '_temp_staging_directory',
            calculate => q{ return $_temp_staging_directory . '/svs.lq'; },
        },
        #output_file => {
        #    type => 'String',
        #    doc  => 'output novo config file',
        #    is_output => 1,
        #},
        novoalign_path => {
            type => 'String',
            doc  => 'novoalign executeable path to use',
            default_value => '/gscuser/kchen/bin/novoalign-2.05.13',
        },
        #novoalign_ref_index => {
        #   type => 'String',
        #    doc  => 'Path to novoalign reference sequence index',
        #    default_value => '/gscuser/kchen/sata114/kchen/Hs_build36/all_fragments/Hs36_rDNA.fa.k14.s3.ndx',
        #},
        novo2sam_path => {
            type => 'String',
            doc  => 'Path to novoalign reference sequence index',
            default_value => '/gscuser/kchen/1000genomes/analysis/scripts/novo2sam.pl',
        },
        platform => {
            type => 'String',
            doc  => 'Path to novoalign reference sequence index',
            default_value => 'SLX',
        },
        samtools_version => {
            type => 'String',
            doc  => 'samtools version to use in this process',
            default_value =>  Genome::Model::Tools::Sam->default_samtools_version,
            valid_values  => [Genome::Model::Tools::Sam->available_samtools_versions],
        },
        samtools_path => {
            type => 'String',
            calculate_from => 'samtools_version',
            calculate => q{ return Genome::Model::Tools::Sam->path_for_samtools_version($samtools_version); },
            doc => 'path to samtools executable',
        },
        breakdancer_version => {
            type => 'String',
            doc  => 'breakdancer version to use in this process',
            default_value =>  Genome::Model::Tools::Breakdancer->default_breakdancer_version,
            valid_values  => [Genome::Model::Tools::Breakdancer->available_breakdancer_versions],
        },
        breakdancer_path => {
            type => 'String',
            calculate_from => 'breakdancer_version',
            calculate => q{ return Genome::Model::Tools::Breakdancer->breakdancer_max_command_for_version($breakdancer_version); },
            doc => 'path to breakdancer executable',
        },

    ],
    has_param => [
        lsf_resource => {
            default_value => "-R 'select[mem>24000] rusage[mem=24000] -M 24000000'", #novoalign needs this memory usage 8G to run
        },
    ],
    has_constant => [
        _variant_type => {
            type => 'String',
            default => 'svs',
            doc => 'variant type that this module operates on, overload this in submodules accordingly',
        },
    ],
};

sub _create_temp_directories {
    my $self = shift;
    $ENV{TMPDIR} = $self->output_directory;
    return $self->SUPER::_create_temp_directories(@_);
}


sub _filter_variants {
    my $self     = shift;
    my $cfg_file = $self->config_file;
    my (%mean_insertsize, %std_insertsize, %readlens);

    my $fh = Genome::Sys->open_file_for_reading($cfg_file) or die "unable to open config file: $cfg_file";
    while (my $line = $fh->getline) {
        next unless $line =~ /\S+/;
        chomp $line;
        my ($mean)   = $line =~ /mean\w*\:(\S+)\b/i;
        my ($std)    = $line =~ /std\w*\:(\S+)\b/i;
        my ($lib)    = $line =~ /lib\w*\:(\S+)\b/i;
        my ($rd_len) = $line =~ /readlen\w*\:(\S+)\b/i;

        ($lib) = $line =~ /samp\w*\:(\S+)\b/i unless defined $lib;
        $mean_insertsize{$lib} = int($mean + 0.5);
        $std_insertsize{$lib}  = int($std  + 0.5);
        $readlens{$lib}        = $rd_len;
    }
    $fh->close;

    my %fastqs;
    my $dir = $self->detector_directory;

    opendir (DIR, $dir) or die "Failed to open directory $dir\n";
    my $prefix;
    for my $fastq (grep{/\.fastq/} readdir(DIR)){
        for my $lib (keys %mean_insertsize) {
            #if ($fastq =~/^(\S+)\.\S+${lib}\.\S*([12])\.fastq/) {
            if ($fastq =~/^(\S+)\.${lib}\.\S*([12])\.fastq/) {
                $prefix = $1;
                my $id  = $2;
                #push @{$fastqs{$lib}{$id}}, $fastq if defined $id;
                push @{$fastqs{$lib}{$id}}, $dir.'/'.$fastq if defined $id;
                last;
            }
        }
    }
    closedir(DIR);

    #Move breakdancer_config to output_directory so TigraValidation
    #can use it to parse out skip_libraries
    my $bd_cfg = $dir . '/breakdancer_config';
    if (-s $bd_cfg) {
        copy $bd_cfg, $self->_temp_staging_directory;
    }
    else {
        $self->warning_message("Failed to find breakdancer_config from detector_directory: $dir");
    }

    $prefix = $self->_temp_staging_directory . "/$prefix";

    my @bams2remove; 
    my @librmdupbams;
    my @novoaligns;
    my %headerline;

    my $novo_path     = $self->novoalign_path;
    my $novosam_path  = $self->novo2sam_path;
    my $samtools_path = $self->samtools_path;

    #my $ref_seq_model = Genome::Model::ImportedReferenceSequence->get(name => 'NCBI-human');
    #my $ref_seq_dir   = $ref_seq_model->build_by_version('36')->data_directory;
    #my $ref_seq_idx   = $ref_seq_dir.'/all_sequences.fasta.fai';
    my $ref_seq     = $self->reference_sequence_input;
    my $ref_seq_idx = $ref_seq . '.fai';
    unless (-s $ref_seq_idx) {
        $self->error_message("Failed to find ref seq fasta index file: $ref_seq_idx");
        die;
    }

    #FIXME hardcode for this index right now and add human build37 to elsif block. 
    #But this is bad and sits in ken's directory. Change this asap.
    my $novo_idx;
    if ($ref_seq =~ /build101947881/) {
        $novo_idx = '/gscuser/kchen/sata114/kchen/Hs_build36/all_fragments/Hs36_rDNA.fa.k14.s3.ndx';
    }
    else {
        die "Now NovoRealign only applied to NCBI-human-Build36, not " . $ref_seq;
    }

    for my $lib (keys %fastqs) {
        my @read1s = @{$fastqs{$lib}{1}};
        my @read2s = @{$fastqs{$lib}{2}};
        my $line   = sprintf "\@RG\tID:%s\tPU:%s\tLB:%s", $lib, $self->platform, $lib;
        $headerline{$line} = 1;
        my @bams;
        my $cmd;
        for (my $i=0; $i<=$#read1s; $i++) {
            my $fout_novo = "$prefix.$lib.$i.novo";
            $cmd = $novo_path . ' -d '. $novo_idx . " -f $read1s[$i] $read2s[$i] -i $mean_insertsize{$lib} $std_insertsize{$lib} > $fout_novo";

            $self->_run_cmd($cmd);
            push @novoaligns,$fout_novo;
            
            my $sort_prefix = "$prefix.$lib.$i";
            #$cmd = $novosam_path . " -g $lib -f ".$self->platform." -l $lib $fout_novo | ". $samtools_path. " view -b -S - -t /gscuser/kchen/reference_sequence/in.ref_list | ".$samtools_path." sort - $sort_prefix";
            $cmd = $novosam_path . " -g $lib -f ".$self->platform." -l $lib $fout_novo | ". $samtools_path. " view -b -S - -t ". $ref_seq_idx .' | ' . $samtools_path." sort - $sort_prefix";
            $self->_run_cmd($cmd);
            push @bams, $sort_prefix.'.bam';
            push @bams2remove, $sort_prefix.'.bam';
        }
    
        if ($#bams>0) {
            #TODO using gmt command modules
            $cmd = $samtools_path ." merge $prefix.$lib.bam ". join(' ', @bams);
            $self->_run_cmd($cmd);
            push @bams2remove, "$prefix.$lib.bam";
        }
        else {
            #`mv $bams[0] $prefix.$lib.bam`;
            rename $bams[0], "$prefix.$lib.bam";
        }

        $cmd = $samtools_path." rmdup $prefix.$lib.bam $prefix.$lib.rmdup.bam";
        $self->_run_cmd($cmd);
        push @librmdupbams, "$prefix.$lib.rmdup.bam";
    }

    my $header_file = $prefix . '.header';
    my $header = Genome::Sys->open_file_for_writing($header_file) or die "fail to open $header_file for writing\n";
    for my $line (keys %headerline) {
        $header->print("$line\n");
    }
    $header->close;

    my $cmd = $samtools_path . " merge -h $header_file $prefix.novo.rmdup.bam ". join(' ', @librmdupbams);
    $self->_run_cmd($cmd);
    
    my $out_file = "$prefix.novo.cfg";

    my $novo_cfg = Genome::Sys->open_file_for_writing($out_file) or die "failed to open $out_file for writing\n";
    for my $lib (keys %fastqs) {
        $novo_cfg->printf("map:$prefix.novo.rmdup.bam\tmean:%s\tstd:%s\treadlen:%s\tsample:%s\texe:samtools view\n",$mean_insertsize{$lib},$std_insertsize{$lib},$readlens{$lib},$lib);
    }
    $novo_cfg->close;

    unlink (@bams2remove, @librmdupbams, @novoaligns, $header_file);
    unlink glob($self->_temp_staging_directory."/*.bam");   #In case leftover bam

    #my $bd_run = Genome::Model::Tools::DetectVariants2::Breakdancer->create(
    #    aligned_reads_input         => $self->aligned_reads_input,
    #    control_aligned_reads_input => $self->control_aligned_reads_input,
    #    reference_sequence_input    => $self->reference_sequence_input,
    #    output_directory            => $self->_temp_staging_directory,
    #    config_file                 => $out_file,
    #    sv_params                   => '-g -h:-t',
    #);
    #unless ($bd_run->execute) {
    #    $self->error_message("Failed to run Breakdancer on Novoalign file: $out_file");
    #    die;
    #}
    
    #my $bd_out_hq          = $self->_temp_staging_directory.'/'.$self->_sv_base_name; #breakdancer under DV2 api will output svs.hq
    my $bd_out_hq_filtered = $self->pass_staging_output;
    my $bd_out_lq_filtered = $self->fail_staging_output;
    my $bd_in_hq           = $self->detector_directory .'/svs.hq';  #DV2::Filter does not have _sv_base_name preset

    my $bd_path = $self->breakdancer_path;

    unless (-s $out_file) {
        $self->error_message("novo.cfg file $out_file is not valid");
        die;
    }

    $cmd = $bd_path . ' -t '. $out_file .' > '. $bd_out_hq_filtered;
    $self->_run_cmd($cmd);

    #rename $bd_out_hq, $bd_out_hq_filtered;

    my $bd_in_hq_fh  = Genome::Sys->open_file_for_reading($bd_in_hq) or die "Failed to open $bd_in_hq for reading\n";
    my $bd_out_hq_fh = Genome::Sys->open_file_for_reading($bd_out_hq_filtered) or die "Failed to open $bd_out_hq_filtered for reading\n";
    my $bd_out_lq_fh = Genome::Sys->open_file_for_writing($bd_out_lq_filtered) or die "Failed to open $bd_out_lq_filtered for writing\n";

    my %filter_match;

    while (my $line = $bd_out_hq_fh->getline) {
        next if $line =~ /^#/;
        my $match = _get_match_key($line);
        $filter_match{$match} = 1;
    }

    while (my $l = $bd_in_hq_fh->getline) {
        next if $l =~ /^#/;
        my $match = _get_match_key($l);
        $bd_out_lq_fh->print($l) unless exists $filter_match{$match};
    }

    $bd_in_hq_fh->close;
    $bd_out_hq_fh->close;
    $bd_out_lq_fh->close;

    return 1;
}


sub _validate_output {
    my $self = shift;

    unless(-d $self->output_directory){
        die $self->error_message("Could not validate the existence of output_directory");
    }
    
    my @files = glob($self->output_directory."/svs.hq");
    unless (@files) {
        die $self->error_message("Failed to get svs.hq");
    }
    return 1;
}


sub _get_match_key {
    my $line = shift;
    my @columns = split /\s+/, $line;
    #compare chr1 pos1 chr2 pos2 sv_type 5 columns
    my $match = join '-', $columns[0], $columns[1], $columns[3], $columns[4], $columns[6];
    return $match;
}


sub _run_cmd {
    my ($self, $cmd) = @_;
    
    unless (Genome::Sys->shellcmd(cmd => $cmd)) {
        $self->error_message("Failed to run $cmd");
        die $self->error_message;
    }
    return 1;
}

1;
