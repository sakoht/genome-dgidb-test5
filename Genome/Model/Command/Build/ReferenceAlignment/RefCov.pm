package Genome::Model::Command::Build::ReferenceAlignment::RefCov;

use strict;
use warnings;

use Genome;

class Genome::Model::Command::Build::ReferenceAlignment::RefCov {
    is => ['Genome::Model::Event'],
    has => [
        _sorted_bams => {
            is => 'Array',
            is_optional => 1,
        },
    ],
};

sub help_brief {
    "Use ref-cov to calculate coverage metrics for cDNA or RNA";
}

sub help_synopsis {
    return <<"EOS"
    genome model build reference-alignment ref-cov --model-id=? --build-id=? 
EOS
}

sub help_detail {
    return <<EOS 
This command is usually called as part of the add-reads process
EOS
}

sub bsub_rusage {
    return "-R 'select[type==LINUX64]'";
}

sub sorted_instrument_data_assignments {
    my $self = shift;
    my $build = $self->build;
    my @sorted_idas = sort { $a->instrument_data_id <=> $b->instrument_data_id } $build->instrument_data_assignments;
    return @sorted_idas;
}

sub sorted_instrument_data_ids {
    my $self = shift;
    my @seq_ids;
    my @sorted_idas = $self->sorted_instrument_data_assignments;
    for my $idas (@sorted_idas) {
        my @alignments = $idas->alignments;
        unless (@alignments) {
            $self->error_message('No alignments found for instrument data '. $idas->instrument_data_id);
            return;
        }
        for my $alignment (@alignments) {
            my @bam_files = $alignment->alignment_bam_file_paths;
            unless (@bam_files) { next; }
            if ($alignment->force_fragment) {
                push @seq_ids, $alignment->_fragment_seq_id;
            } else {
                push @seq_ids, $alignment->instrument_data_id;
            }
        }
    }
    return @seq_ids;
}

sub sorted_bam_files {
    my $self = shift;
    my @sorted_bam_files;
    unless (defined($self->_sorted_bams)) {
        my @sorted_idas = $self->sorted_instrument_data_assignments;
        for my $idas (@sorted_idas) {
            my @alignments = $idas->alignments;
            unless (@alignments) {
                $self->error_message('No alignments found for instrument data '. $idas->instrument_data_id);
                return;
            }
            for my $alignment (@alignments) {
                push @sorted_bam_files, $alignment->alignment_bam_file_paths;
            }
        }
        $self->_sorted_bams(\@sorted_bam_files);
    } else {
        @sorted_bam_files = @{$self->_sorted_bams};
    }
    return @sorted_bam_files;;
}


sub progression_array_ref {
    my $self = shift;

    my @sorted_bam_files = $self->sorted_bam_files;
    my @progression;
    my @progression_instance;
    for my $bam_file (@sorted_bam_files) {
        push @progression_instance, $bam_file;
        my @current_instance = @progression_instance;
        push @progression, \@current_instance;
    }
    return \@progression;
}

sub progression_count {
    my $self = shift;
    my @sorted_bam_files = $self->sorted_bam_files;
    my $progression_count = scalar(@sorted_bam_files);
    return $progression_count;
}

sub execute {
    my $self = shift;

    my $ref_cov_dir = $self->build->reference_coverage_directory;
    unless (Genome::Utility::FileSystem->create_directory($ref_cov_dir)) {
        $self->error_message('Failed to create ref_cov directory '. $ref_cov_dir .":  $!");
        return;
    }

    # Run ref-cov on each accumulated iteration or progression
    # produces a reference coverage stats file for each iteration and relative coverage
    unless ($self->verify_progressions) {
        my $progression_array_ref = $self->progression_array_ref;
        $self->status_message('Progressions look like: '. Data::Dumper::Dumper($progression_array_ref));
        #parallelization starts here
        require Workflow::Simple;
        #$Workflow::Simple::store_db=0;

        my $op = Workflow::Operation->create(
            name => 'RefCov Progression',
            operation_type => Workflow::OperationType::Command->get('Genome::Model::Tools::RefCov::ProgressionInstance')
        );

        $op->parallel_by('bam_files');

        my $output = Workflow::Simple::run_workflow_lsf(
            $op,
            'output_directory' => $ref_cov_dir,
            'bam_files' => $progression_array_ref,
            'target_query_file' => $self->build->genes_file
        );

        #check workflow for errors 
        if (!defined $output) {
            foreach my $error (@Workflow::Simple::ERROR) {
                $self->error_message($error->error);
            }
            return;
        } else {
            my $results = $output->{result};
            my $result_instances = $output->{instance};
            for (my $i = 0; $i < scalar(@$results); $i++) {
                my $rv = $results->[$i];
                if ($rv != 1) {
                    $self->error_message("Workflow had an error while running progression instance: ". $result_instances->[$i]); 
                    die($self->error_message);
                }
            }
        }
    }
    unless ($self->verify_progressions) {
        $self->error_message('Failed to verify progression directories after running ref-cov');
        return;
    }

    my @progression_stats_files = $self->progression_stats_files;
    my $final_stats_file = $progression_stats_files[-1];
    unless (Genome::Utility::FileSystem->validate_file_for_reading($final_stats_file)) {
        $self->error_message("Failed to validate stats file '$final_stats_file' for reading:  $!");
        die($self->error_message);
    }
    my $stats_file = $self->build->coverage_stats_file;
    unless ( -l $stats_file) {
        unless (symlink($final_stats_file,$stats_file)) {
            $self->error_message("Failed to create final stats progression symlink:  $!");
            die($self->error_message);
        }
    }

    my @final_bias_files = glob ($ref_cov_dir .'/bias_'. $self->progression_count .'_*');
    for my $final_bias_file (@final_bias_files) {
        unless ($final_bias_file =~ /bias_\d+_(\w+)/) {
            $self->error_message('Failed to parse bias file name '. $final_bias_file);
            die($self->error_message);
        }
        my $size = $1;
        my $bias_file = $self->build->relative_coverage_file($size);
        unless ( -l $bias_file) {
            unless (symlink($final_bias_file,$bias_file)) {
                $self->error_message("Failed to create final bias progression symlink:  $!");
                die($self->error_message);
            }
        }
    }

    my @progression_instrument_data_ids = $self->sorted_instrument_data_ids;
    unless (-s $self->build->coverage_progression_file) {
        unless (Genome::Model::Tools::RefCov::Progression->execute(
            stats_files => \@progression_stats_files,
            instrument_data_ids => \@progression_instrument_data_ids,
            sample_name => $self->model->subject_name,
            output_file => $self->build->coverage_progression_file,
        ) ) {
            $self->error_message('Failed to execute the progression for progressions:  '. join("\n",@progression_stats_files));
            die($self->error_message);
        }
    }

    unless (-s $self->build->breakdown_file) {
        my @sorted_bam_files = $self->sorted_bam_files;
        my $breakdown_cmd = '/gscuser/jwalker/svn/TechD/RefCov/bin/breakdown-64.pl '. $ref_cov_dir .' '. join(' ',@sorted_bam_files);
        Genome::Utility::FileSystem->shellcmd(
            cmd => $breakdown_cmd,
            input_files => \@sorted_bam_files,
            output_files => [$self->build->breakdown_file],
        );
    }
    
    my $report_generator = Genome::Model::ReferenceAlignment::Report::ReferenceCoverage->create(build_id => $self->build->id);
    unless ($report_generator) {
        $self->error_message('Error creating ReferenceCoverage report generator: '. Genome::Model::ReferenceAlignment::Report::ReferenceCoverage->error_message());
        die($self->error_message);
    }
    my $report = $report_generator->generate_report;
    unless ($report) {
        $self->error_message('Error generating report '. $report_generator->report_name .': '. Genome::Model::ReferenceAlignment::Report::ReferenceCoverage->error_message());
        $report_generator->delete;
        die($self->error_message);
    }
    if ($self->build->add_report($report)) {
        $self->status_message('Saved report: '. $report);
    } else {
        $self->error_message('Error saving '. $report.'. Error: '. $self->build->error_message);
        die($self->error_message);
    }
    my $xsl_file = $report_generator->get_xsl_file_for_html;
    unless (-e $xsl_file) {
        $self->error_message('Failed to find xsl file for ReferenceCoverage report');
        die($self->error_message);
    }
    my $xslt = Genome::Report::XSLT->transform_report(
        report => $report,
        xslt_file => $xsl_file,
    );
    unless ($xslt) {
        $self->error_message('Failed to generate XSLT for ReferenceCoverage report');
        die($self->error_message);
    }
    my $report_subdirectory = $self->build->reports_directory .'/'. $report->name_to_subdirectory($report->name);
    my $report_file = $report_subdirectory .'/report.'. ($xslt->{output_type} || 'html');
    my $fh = Genome::Utility::FileSystem->open_file_for_writing( $report_file );
    $fh->print( $xslt->{content} );
    $fh->close;
    my $mail_dest = 'jwalker@genome.wustl.edu';
    my $link = 'https://gscweb.gsc.wustl.edu'. $report_file;
    my $sender = Mail::Sender->new({
        smtp => 'gscsmtp.wustl.edu',
        from => 'jwalker@genome.wustl.edu',
        replyto => 'jwalker@genome.wustl.edu',
    });
    $sender->MailMsg({
        to => $mail_dest,
        subject => 'Genome Model '. $self->model->name .' Reference Coverage Report for Build '. $self->build->id,
        msg => $link,
    });
    return $self->verify_successful_completion;
}

sub progression_stats_files {
    my $self = shift;

    my @stats_files = map { $self->build->reference_coverage_directory .'/STATS_'. $_ .'.tsv' } (1 .. $self->progression_count);
    return @stats_files;
}

sub verify_progressions {
    my $self = shift;
    my @progression_stats_files = $self->progression_stats_files;
    for my $progression_stats_file (@progression_stats_files) {
        unless (-e $progression_stats_file) {
            return;
        }
        unless (-f $progression_stats_file) {
            return;
        }
        unless (-s $progression_stats_file) {
            return;
        }
    }
    return 1;
}

sub verify_successful_completion {
    my $self = shift;

    unless ($self->verify_progressions) {
        $self->error_message('Failed to verify progressions!');
        die($self->error_message);
    }
    my @files = (
        $self->build->coverage_progression_file,
        $self->build->coverage_stats_file,
        $self->build->breakdown_file
    );
    my @SIZES = qw/SMALL MEDIUM LARGE/;
    for my $size (@SIZES) {
        push @files, $self->build->relative_coverage_file($size);
    }
    for my $file (@files) {
        $self->check_output_file_existence($file);
    }
    return 1;
}

sub check_output_file_existence {
    my $self = shift;
    my $file = shift;

    unless (-e $file) {
        $self->error_message('Missing reference coverage output file '. $file);
        return;
    }
}

1;
