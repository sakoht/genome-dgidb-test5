
package Genome::Model::Tools::Picard::SamToFastq;

use strict;
use warnings FATAL => 'all';

use Genome;

class Genome::Model::Tools::Picard::SamToFastq {
    is  => 'Genome::Model::Tools::Picard',
    has_input => [
        input => {
            is  => 'String',
            doc => 'Input SAM/BAM file to extract reads from. Required.',
        },
        fastq => {
            is          => 'String',
            doc         => 'Output fastq file (single-end fastq or, if paired, first end of the pair fastq). Required.',
        },
        fastq2 => {
            is          => 'String',
            doc         => 'Output fastq file (if paired, second end of the pair fastq). Default value: null.',
            is_optional => 1,
        },
        fragment_fastq => {
            is          => 'String',
            doc         => 'Output fastq file for bams which contain a mix of fragments & pairs -- required if paired',
            is_optional => 1,
        },
        no_orphans      => {
            is => 'Boolean',
            doc => 'Ignore orphaned reads (good reads, but whose mates were marked as failing quality filtering)',
            default_value => 0,
        },
        read_group_id => {
            is          => 'String',
            doc         => 'Limit to a single read group',
            is_optional => 1,
        }
    ],
};

sub help_brief {
    'Tool to create FASTQ file from SAM/BAM using Picard';
}

sub help_detail {
    return <<EOS
    Tool to create FASTQ file from SAM/BAM using Picard.  For Picard documentation of this command see:
    http://picard.sourceforge.net/command-line-overview.shtml#SamToFastq
EOS
}

sub execute {
    my $self = shift;

    my $picard_version = $self->use_version;

    if ($self->fastq2 && !$self->fragment_fastq) {
        $self->error_message("you must specify a fragment fastq file output if you are using pairs!");
        return;
    }

    my $input_file = $self->input;
    my $unlink_input_bam_on_end = 0;
   
    if (defined $self->read_group_id) {
        $unlink_input_bam_on_end = 1;
        my $samtools_path = Genome::Model::Tools::Sam->path_for_samtools_version;
        
        my $temp = Genome::Sys->base_temp_directory;
        my $temp_bam_file = $temp . "/temp_rg." . $$ . ".bam";
	my $samtools_check_cmd = sprintf("%s view -r%s %s | head -1",
                                          $samtools_path, $self->read_group_id, $input_file);
        my  $samtools_check_output = `$samtools_check_cmd`;

	if (length($samtools_check_output) == 0) {
		$self->error_message ("Read Group X identified in the imported BAM header seems to have zero reads in the BAM file.  The BAM file header should be repaired in-place.  Subsequent re-runs of this pipeline will then not fail, and will shortcut past the alignments for other read groups.");
		die $self->error_message;
	} 

	my $samtools_strip_cmd = sprintf("%s view -h -r%s %s | samtools view -S -b -o %s -",
			$samtools_path, $self->read_group_id, $input_file, $temp_bam_file);

	Genome::Sys->shellcmd(cmd=>$samtools_strip_cmd, 
			output_files=>[$temp_bam_file],
			skip_if_output_is_present=>0);


	my $sorted_temp_bam_file = $temp . "/temp_rg.sorted." . $$ . ".bam";

	my $sort_cmd = Genome::Model::Tools::Sam::SortBam->create(file_name=>$temp_bam_file, name_sort=>1, output_file=>$sorted_temp_bam_file);

	unless ($sort_cmd->execute) {
		$self->error_message("Failed sorting reads into name order for iterating");
		return;
	}

	unlink($temp_bam_file);        
	$input_file = $sorted_temp_bam_file;
    }

    my $picard_dir = $self->picard_path;
    my $picard_jar_path = $picard_dir . "/sam-".$picard_version.".jar";
    my $sam_jar_path = $picard_dir . "/picard-".$picard_version.".jar";
    my $tool_jar_path = $self->class->base_dir . "/GCSamToFastq.jar";

    my $cp = join ":", ($picard_jar_path, $sam_jar_path, $tool_jar_path);

    my $jvm_options = $self->additional_jvm_options || '';
    my $java_vm_cmd = 'java -Xmx'. $self->maximum_memory .'g -XX:MaxPermSize=' . $self->maximum_permgen_memory . 'm ' . $jvm_options . ' -cp '. $cp . ' edu.wustl.genome.samtools.GCSamToFastq ';


    my $args = '';

    $args .= ' INPUT=' . "'" . $input_file . "'";
    $args .= ' FASTQ=' . "'" . $self->fastq . "'";
    $args .= ' SECOND_END_FASTQ=' . "'" . $self->fastq2 . "'" if ($self->fastq2);
    $args .= ' FRAGMENT_FASTQ=' . "'" . $self->fragment_fastq. "'" if ($self->fragment_fastq);
    $args .= ' NO_ORPHAN=true' if ($self->no_orphans);

    $java_vm_cmd .= $args;

    print $java_vm_cmd . "\n";

    my @output_files = ($self->fastq);
    push @output_files, $self->fastq2 if $self->fastq2;
#    push @output_files, $self->fragment_fastq if $self->fragment_fastq;

    $self->run_java_vm(
		    cmd          => $java_vm_cmd,
		    input_files  => [ $input_file ],
#        output_files => \@output_files,
		    skip_if_output_is_present => 0,
		    );


    # BAM v. FASTQ read counts
    my $bam_read_count = $self->_read_count_for_bam($input_file);
    return if not $bam_read_count;
    $self->status_message("$bam_read_count reads in BAM: $input_file");
    my $fastq_read_count = $self->_read_count_for_fastq(@output_files);
    return if not $fastq_read_count;
    $self->status_message("$fastq_read_count reads in FASTQ: ".join(' ', @output_files));

    # RM Input BAM
    unlink $input_file if ($unlink_input_bam_on_end && $self->input ne $input_file);

    # Compare read counts
    if ( $bam_read_count ne $fastq_read_count ) {
        $self->error_message("Different number of reads in BAM ($bam_read_count) and FASTQ ($fastq_read_count)");
        return;
    }

    return 1;
}

sub _read_count_for_bam {
    my ($self, $bam) = @_;

    Carp::confess('No bamto get read count!') if not $bam;

    my $tmpdir = Genome::Sys->base_temp_directory;
    my $flagstat_file = $tmpdir.'/flagstat';
    my $gmt = Genome::Model::Tools::Sam::Flagstat->create(
        bam_file => $bam,
        output_file => $flagstat_file,
    );
    if ( not $gmt ) {
        $self->error_message('Failed to create gmt same flagstat!');
        return;
    }
    $gmt->dump_status_messages(1);
    my $ok = $gmt->execute;
    if ( not $ok ) {
        $self->error_message('Failed to execute gmt sam flagstat!');
        return;
    }

    my $flagstat = Genome::Model::Tools::Sam::Flagstat->parse_file_into_hashref($flagstat_file);
    if ( not $flagstat ) {
        $self->error_message('Failed to get metrics from flagstat file: '.$flagstat_file);
        return;
    }

    if ( not defined $flagstat->{total_reads} ) {
        $self->error_message('No total reads from flagstat file!');
        return;
    }

    return $flagstat->{total_reads};
}

sub _read_count_for_fastq {
    my ($self, @fastqs) = @_;

    Carp::confess('No fastq to get read count!') if not @fastqs;

    my $read_count;
    for my $fastq ( @fastqs ) {
        my $line_count = `wc -l < $fastq`;
        if ( $? or not $line_count ) {
            $self->error_message("Line count on fastq ($fastq) failed : $?");
            return;
        }

        chomp $line_count;
        if ( ($line_count % 4) != 0 ) {
            $self->error_message("Line count ($line_count) on fastq ($fastq) not divisble by 4.");
            return;
        }
        $read_count += $line_count / 4;
    }

    return $read_count;
}

1;
__END__

