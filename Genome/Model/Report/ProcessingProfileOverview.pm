package Genome::Model::Report::ProcessingProfileOverview;

use strict;
use warnings;

use Genome;

use App::Report;
use CGI;
use IO::String;
use Data::Dumper;
use Template;
use POSIX; 

my $base_template_path = __PACKAGE__->_base_path_for_templates;

class Genome::Model::Report::ProcessingProfileOverview {
    is => 'Genome::Model::Report',
    has => [ 
        # the name is essentially constant
        name => { default_value => 'Processing Profile Overview' },
        report_templates => {
            is => 'String',
            is_many => 1,
            default_value => [
                 "$base_template_path.html.tt2",
                 "$base_template_path.txt.tt2",
            ],
            doc => 'The paths of template(s) to use to format the report. (In .tt2 format)',
        },
    ],
};

sub _generate_data {
    my $self = shift;
    my $template = shift;

    my @templates = $self->report_templates;
    unless (@templates) {
        die "No report templates assigned! Cannot generate any content."
    }

    print "running _generate_data\n";

    my $style = $self->get_css();
    my $data = { description => $self->generate_report_brief };

    for my $template (@templates) {
        my $content = $self->generate_report_detail($template);
        my ($format,$key);
        if ($content =~ /\<\s*HTML/i) {
            $format = 'HTML';
            $key = 'html';
        }
        else {
            $format = 'text';
            $key = 'txt'; 
        }
        if (exists $data->{$key}) {
            die "Multiple templates return content in $format format. This is not supported, sadly."
                . " Error processing $template";
        }
        $data->{$key} = $content;
    };
    return $data;

}

sub _base_path_for_templates {
    my $module = __PACKAGE__;
    $module =~ s/::/\//g;
    $module .= '.pm';
    my $module_path = $INC{$module};
    unless ($module_path) {
        die "Module " . __PACKAGE__ . " failed to find its own path! Checked for $module in \%INC...";
    }
    return $module_path;
}

# all of these below are only called if _generate_data tries to do so? 


sub generate_report_brief {
    my $self=shift;
    print "calling generate_report_brief\n";
    return "Processing Profile Overview for " . $self->model_id . " (" . $self->model_name . ") as of " . UR::Time->now;
}

sub generate_report_detail {
    my $self = shift;
    my $template = shift;
    unless ($template) {
        die "Please specify which template to use for this report.";
    }

$DB::single = 1;   

    print "calling generate_report_detail\n";

    my $build = $self->build;
    my $model = $self->model;
    my $pprofile = $model->processing_profile;
    my $subject_name = $model->subject_name;
    my $sample;
    my @project_list;
    my @model_build_list = $model->builds;
    my $style = $self->get_css();
    my $content = '';

#   REALLY oughta get this to work correctly... not all subjects are samples.
    if ($model->subject_type eq 'sample_name') {
        $sample = Genome::Sample->get(name=>$subject_name);
        @project_list = Genome::Project->get(sample_names=>$sample->name);
    }

    my @vars = (
        time_now           => UR::Time->now,
        build              => $build,
        model              => $model,
        pprofile           => $pprofile,
#        subject_name       => $subject_name,
        style              => $style,
#        sample             => $sample,
#        project_list       => \@project_list,
#        model_build_list   => \@model_build_list,
    );

    my $tt = Template->new({
        ABSOLUTE => 1,
    }) || die "$Template::ERROR\n";

    my $rv = $tt->process($template, { @vars }, \$content ) || die $$tt->error(), "\n";
    if ($rv != 1) {
        die "Bad return value from template processing for overview report generation: $rv ";
    }
#    unless ($content) {
#        die "No content returned from template processing!";
#    }

    my $body = IO::String->new();  
    die $! unless $body;
    $body->print($content);
    $body->seek(0, 0);
    return join('', $body->getlines);
}

sub get_css {
#    my $module_path = $INC{"Genome/Model/Report/ProcessingProfileOverview.pm"};
#    die 'failed to find module path!' unless $module_path;
    
    ## get CSS resources
    my $css_file = "Genome/Model/Report/Overview.css";
    my $css_fh = IO::File->new($css_file);
    unless ($css_fh) {
        die "failed to open file $css_file!"; 
    }
    my $page_css = join('',$css_fh->getlines);

}

1;
