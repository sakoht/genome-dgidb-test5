package Genome::Report::Command::Xslt;
#:adukes check

use strict;
use warnings;

use Genome;

require Cwd;

class Genome::Report::Command::Xslt {
    is => 'Genome::Report::Command',
    has => [ 
    report_directory => { 
        is => 'Text', 
        doc => 'Report directory.',
    },
    xsl_file => {
        is => 'Text',
        doc => 'Xslt file to use to transform the report.',
    },
    ],
    has_optional => [
    output_file => {
        is => 'Text',
        doc => 'Output file for the transformed report.  Default is to use the current directory, the report\'s name and the xsl media type (as the exetension).',
    },
    force => {
        is =>'Boolean',
        default_value => 0,
        doc => 'Force overwrite if output file exists.',
    },
    ],
};

#< Helps >#
sub help_brief {
    return "Transform a report with XSLT";
}

sub help_detail {
    return $_[0]->help_brief;
}

#< Report >#
sub report {
    my $self = shift;

    unless ( $self->{_report} ) { 
        $self->{_report} = Genome::Report->create_report_from_directory($self->report_directory);
    }

    return $self->{_report};
}

#< Command >#
sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_)
        or return;

    # Report
    unless ( $self->report ) {
        $self->error_message("Can't get report.  See above error.");
        $self->delete;
        return;
    }

    # Xsl file
    unless ( $self->xsl_file ) {
        $self->error_message("No xsl file given.");
        $self->delete;
        return;
    }
        
    return $self;
}

sub execute {
    my $self = shift;

    my $xslt = Genome::Report::XSLT->transform_report(
        report => $self->report,
        xslt_file => $self->xsl_file,
    ) or return $self->error_message("Can't tranform report with xsl file: ".$self->xsl_file);

    unless ( $self->output_file ) {
        $self->output_file(
            sprintf(
                '%s/%s.%s',
                Cwd::getcwd(),
                Genome::Utility::Text::sanitize_string_for_filesystem($self->report->name),
                $xslt->{output_type},
            )
        );
    }
    unlink $self->output_file if $self->force and -e $self->output_file;
    my $fh = Genome::Utility::FileSystem->open_file_for_writing( $self->output_file );
    unless ( $fh ) {
        $self->error_message("Can't opening output file.  See above error.");
        return;
    }
    $fh->print( $xslt->{content} );
    $fh->close;

    $self->status_message("Transformed report.");
    
    return 1;
}

1;

#$HeadURL$
#$Id$
