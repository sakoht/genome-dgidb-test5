package Genome::Model::Event::Build::DeNovoAssembly::Report;

use strict;
use warnings;

use Genome;

use File::Path;

class Genome::Model::Event::Build::DeNovoAssembly::Report {
    is => 'Genome::Model::Event::Build::DeNovoAssembly',
};

sub execute {
    my $self = shift;
    $self->status_message('De novo assembly report...');

    #run stats
    my $tools_base_class = $self->processing_profile->tools_base_class;
    my $metrics_class = $tools_base_class.'::Metrics';
    my $major_contig_length = ( $self->build->processing_profile->name =~ /PGA/ ? 300 : 500 );
    $self->status_message('Assembly directory: '.$self->build->data_directory);
    $self->status_message('Major contig length: '.$major_contig_length);
    my %metrics_params = (
        assembly_directory => $self->build->data_directory,
        major_contig_length => $major_contig_length,
    );
    my $min_contig_length;
    if ( $min_contig_length = $self->_min_contig_length_in_processing_profile ) {
        $metrics_params{min_contig_length} = $min_contig_length;
    }
    my $metrics_tool = $metrics_class->create( %metrics_params );
    if ( not $metrics_tool ) {
        $self->error_message('Failed to create metrics tool: '.$metrics_class);
        return;
    }
    unless( $metrics_tool->execute ) {
        $self->error_message("Failed to create stats");
        return;
    }

    # add assembler info
    my $metrics = $metrics_tool->_metrics;
    for my $name (qw/ assembler_name assembler_version assembler_params coverage read_processor /) {
        $metrics->set_metric($name, $self->build->processing_profile->$name) if defined $self->build->processing_profile->$name;
    }

    $metrics->set_metric('subject_name', $self->model->subject_name);
    $metrics->set_metric('genome_size', $self->build->genome_size);
    $metrics->set_metric('insert_size', $self->build->calculate_average_insert_size);
    my $kmer_used = eval{ $self->build->assembler_kmer_used; };
    $metrics->set_metric('assembler_kmer', $kmer_used) if defined $kmer_used;

    # add previously stored metrics
    $metrics->set_metric('reads_attempted', $self->build->reads_attempted);
    $metrics->set_metric('reads_processed', $self->build->reads_processed);
    $metrics->set_metric('reads_processed_success', $self->build->reads_processed_success);

    # calculate the metrics
    $metrics->calculate_metrics;

    # set metrics on build
    $self->status_message('Set metrics on build...');
    for my $metric_name ( $self->build->metric_names ) {
        my $value = $metrics->get_metric($metric_name);
        $value = 'NA' if not defined $value;
        $self->status_message($metric_name.' => '.$value);
        $self->build->add_metric(
            name => $metric_name,
            value => $value,
        );
    }
    $self->status_message('Set metrics on build...OK');
    
    # save html
    my $genome_dir = Genome->get_base_directory_name;
    my $xslt_file = $genome_dir.'/Model/Build/DeNovoAssembly/Summary.html.xsl';
    my $html = $metrics->transform_xml($xslt_file);
    my $report_directory = $self->build->reports_directory.'/Summary';
    eval{ File::Path::make_path($report_directory); };
    if ( not -d $report_directory ) {
        $self->error_message("Failed to make summary report directory ($report_directory): $@");
        return;
    }
    my $html_file = $report_directory.'/report.html';
    my $fh = eval{ Genome::Sys->open_file_for_writing($html_file); };
    if ( not $fh ) {
        $self->error_message('Failed to open summary report file: '.$html_file);
        return;
    }
    $fh->print($html);
    $fh->close;

    $self->status_message('De novo assembly report...OK');
    return 1;
}

sub _min_contig_length_in_processing_profile {
    my $self = shift;
    my %params = $self->processing_profile->assembler_params_as_hash;
    return if not exists $params{min_contig_length};
    return $params{min_contig_length};
}

1;

