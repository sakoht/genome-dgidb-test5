package Genome::Model::Event::Build::MetagenomicComposition16s::Reports;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';

class Genome::Model::Event::Build::MetagenomicComposition16s::Reports {
    is => 'Genome::Model::Event::Build::MetagenomicComposition16s',
};

sub execute {
    my $self = shift;

    for my $report_name ('summary', 'composition') {
        $self->_generate_and_save_report($report_name);
    }

    return 1;
}

sub _generate_and_save_report {
    my ($self, $name) = @_;

    my $build = $self->build;
    my $class = 'Genome::Model::MetagenomicComposition16s::Report::'.Genome::Utility::Text::string_to_camel_case($name);
    my $generator = $class->create(
        build_id => $build->id,
    );
    unless ( $generator ) {
        $self->error_message("Could not create $name report generator for ".$build->description);
        return;
    }
    my $report = $generator->generate_report;
    unless ( $report ) {
        $self->error_message("Could not generate $name report for ".$build->description);
        return;
    }

    unless ( $build->add_report($report) ) {
        $self->error_message("Could not save $name report for ".$build->description);
    }

    my @datasets = $report->get_datasets;
    unless ( @datasets ) { # not ok
        $self->error_message("No datasets in $name report for ".$build->description);
        return;
    }
    my $file_base = sprintf(
        '%s/%s',
        $build->reports_directory,
        $report->name_to_subdirectory($report->name),
    );

    for my $dataset ( @datasets ) {
        my $dataset_name = $dataset->name;
        my $file = sprintf(
            '%s/%s.%s.tsv',
            $file_base,
            $self->model->subject_name,
            $dataset_name,
        );
        unlink $file if -e $file;
        my $fh = Genome::Utility::FileSystem->open_file_for_writing($file)
            or return; # not ok
        my ($svs) = $dataset->to_separated_value_string(separator => "\t");
        unless ( $svs ) { # not ok
            $self->error_message("Could not get dataset ($dataset) for $name report for ".$build->description);
            return;
        }
        $fh->print($svs);
        $fh->close;
    }

    return $report;
}

1;

#$HeadURL$
#$Id$
