package Genome::Model::Command::Status;

use strict;
use warnings;
use Genome;
use Data::Dumper;
use XML::LibXML;

class Genome::Model::Command::Status {
    is => ['Command'],
    has => [ 
        genome_model_id => { 
            is => 'String', 
            doc => 'Required genome model id upon which the report is run.',
        },
        model   => {
            is => 'Genome::Model',
            id_by => 'genome_model_id',
            doc => "The Model upon which to report the status.",
        },
    ],
    has_optional => [
        section => {
            is => 'String',
            doc => "NOT IMPLEMENTED YET.  The sub-section of the document to return.  Options are 'all', 'events', etc.", 
        }, 
        display_output => {
            is => 'Integer',
            default_value => 1,
            doc => "A flag which lets the user supress the display of XML output to the screen.", 
        }, 
        _doc => {
            is => 'XML::LibXML::Document',
            doc => "The XML tool used to create all nodes of the output XML tree.",
        },
        _xml => {
            is => 'Text',
            doc => "The XML generated by the status call.",
        },
        _job_to_status => {
            is => 'HASH',
            doc => "The XML generated by the status call.",
        },
    ],
};

sub sub_command_sort_position { 8 }

sub execute  {
    my $self = shift;
    my $return_value = 1;
   
    #create the XML doc and add it to the object 
    my $doc = XML::LibXML->createDocument();
    $self->_doc($doc);

    #create the xml nodes and fill them up with data
    #root node
    my $model_status_node = $doc->createElement("model-status");
    my $time = UR::Time->now(); 
    $model_status_node->addChild( $doc->createAttribute("generated-at",$time) );
  
    # model node 
    my $modelnode = $self->get_model_node;
    $model_status_node->addChild($modelnode);

    #builds
    $modelnode->addChild( $self->get_builds_node() );
    
    #processing profile 
    #$modelnode->addChild ( $self->get_processing_profile_node() );
    
    #TODO:  add method to build for logs, reports
    #$modelnode->addChild ( $self->tnode("logs","") );
    #$modelnode->addChild ( $self->get_reports_node );

    #set the build status node to be the root
    $doc->setDocumentElement($model_status_node); 

    #generate the XML string
    $self->_xml($doc->toString(1) );

    #print to the screen if desired
    if ( $self->display_output ) {
        print $self->_xml;
    } 

    return $return_value;
}

sub get_model_node {
    my $self = shift;
    my $doc = $self->_doc;
    
    my $modelnode = $doc->createElement("model");

    my $model = $self->model;

    $modelnode->addChild( $doc->createAttribute("model-id",$model->id) );
    $modelnode->addChild( $doc->createAttribute("model-name",$model->name) );
    $modelnode->addChild( $doc->createAttribute("user_name",$model->user_name) );
    $modelnode->addChild( $doc->createAttribute("creation_date",$model->creation_date) );
    $modelnode->addChild( $doc->createAttribute("processing_profile_name", $model->processing_profile->name) );
    $modelnode->addChild( $doc->createAttribute("sample_name",$model->subject_name) );
    $modelnode->addChild( $doc->createAttribute("subject_id",$model->subject_id) );
    $modelnode->addChild( $doc->createAttribute("subject_name",$model->subject_name) );
    $modelnode->addChild( $doc->createAttribute("subject_type",$model->subject_type) );
    $modelnode->addChild( $doc->createAttribute("subject_class_name",$model->subject_class_name) );    
    $modelnode->addChild( $doc->createAttribute("data_directory",$model->data_directory) );
    return $modelnode; 
}

sub get_reports_node {
    my $self = shift;

    my $report_dir = $self->build->resolve_reports_directory;
    my $reports_node = $self->anode("reports", "directory", $report_dir);
    my @report_list = $self->build->reports;
    for my $each_report (@report_list) {
        my $report_node = $self->anode("report","name", $each_report->name );
        $self->add_attribute($report_node, "subdirectory", $each_report->name_to_subdirectory($each_report->name) );
        $reports_node->addChild($report_node); 
    }

    return $reports_node;
}

sub get_builds_node {
    my $self = shift;
    my $doc = $self->_doc;

    my $builds_list = $doc->createElement("builds");
    my @builds = $self->model->builds;

    for my $build (@builds) {
        my $build_node = $self->get_build_node($build);
        $builds_list->addChild($build_node);
    }

    return $builds_list;

}

sub get_build_node {
    
    my $self = shift; 
    my $build = shift;
    my $doc = $self->_doc;

    my $build_node = $self->anode("build","id",$build->id);
    $build_node->addChild( $self->tnode("date_scheduled",$build->date_scheduled));
    $build_node->addChild( $self->tnode("date_completed",$build->date_completed));
    $build_node->addChild( $self->tnode("build_status",$build->build_status));    
    $build_node->addChild( $self->tnode("elapsed_time", $self->calculate_elapsed_time($build->date_scheduled,$build->date_completed) ));
    return $build_node;

}

sub get_events_node {
    my $self = shift;
    my $doc = $self->_doc;

    my $events_list = $doc->createElement("events");
    my @events = $self->build->events;

    for my $event (@events) {
        my $event_node = $self->get_event_node($event);
        $events_list->addChild($event_node);
    }

    return $events_list;

}

sub get_event_node {
    
    my $self = shift; 
    my $event = shift;
    my $doc = $self->_doc;

    my $lsf_job_status = $self->get_lsf_job_status($event->lsf_job_id);

    my $event_node = $self->anode("event","id",$event->id);
    $event_node->addChild( $doc->createAttribute("command_class",$event->class)); 
        $event_node->addChild( $self->tnode("event_status",$event->event_status));
        $event_node->addChild( $self->tnode("lsf_job_id",$event->lsf_job_id));
        $event_node->addChild( $self->tnode("lsf_job_status",$lsf_job_status));
        $event_node->addChild( $self->tnode("date_scheduled",$event->date_scheduled));
        $event_node->addChild( $self->tnode("date_completed",$event->date_completed));
        $event_node->addChild( $self->tnode("elapsed_time", $self->calculate_elapsed_time($event->date_scheduled,$event->date_completed) ));
        $event_node->addChild( $self->tnode("instrument_data_id",$event->instrument_data_id));
        my $log_file = $event->resolve_log_directory ."/".$event->id.".err";
        $event_node->addChild( $self->tnode("log_file",$log_file));
    return $event_node;

}

sub create_node_with_attribute {
    
    my $self = shift;
    my $node_name = shift;
    my $attr_name = shift;
    my $attr_value = shift;

    my $doc = $self->_doc;
    
    my $node = $doc->createElement($node_name);
    $node->addChild($doc->createAttribute($attr_name,$attr_value));
    return $node;
} 

#helper methods.  just pass through to the more descriptive names 
#anode = attribute node
sub anode {
    my $self = shift;
    return $self->create_node_with_attribute(@_);
}
 
#tnode = text node
sub tnode {
    my $self = shift; 
    return $self->create_node_with_text(@_);
}
 
sub create_node_with_text {
 
    my $self = shift;
    my $node_name = shift;
    my $node_value = shift;

    my $doc = $self->_doc;
    
    my $node = $doc->createElement($node_name);
    if ( defined($node_value) ) {
        $node->addChild($doc->createTextNode($node_value));
    } 
    return $node;

} 

sub add_attribute {
    my $self = shift;
    my $node = shift;
    my $attr_name = shift;
    my $attr_value = shift;

    my $doc = $self->_doc;

    $node->addChild($doc->createAttribute($attr_name,$attr_value) );
    return $node;

}

sub calculate_elapsed_time {
    my $self = shift;
    my $date_scheduled = shift;
    my $date_completed = shift;

    my $diff;

    if ($date_completed) {
        $diff = UR::Time->datetime_to_time($date_completed) - UR::Time->datetime_to_time($date_scheduled);
    } else {
        $diff = time - UR::Time->datetime_to_time( $date_scheduled);
    }

    # convert seconds to days, hours, minutes
    my $seconds = $diff;
    my $days = int($seconds/(24*60*60));
    $seconds -= $days*24*60*60;
    my $hours = int($seconds/(60*60));
    $seconds -= $hours*60*60;
    my $minutes = int($seconds/60);
    $seconds -= $minutes*60;
    my $formatted_time;
    if ($days) {
        $formatted_time = sprintf("%d:%02d:%02d:%02d",$days,$hours,$minutes,$seconds);
    } elsif ($hours) {
        $formatted_time = sprintf("%02d:%02d:%02d",$hours,$minutes,$seconds);
    } elsif ($minutes) {
        $formatted_time = sprintf("%02d:%02d",$minutes,$seconds);
    } else {
        $formatted_time = sprintf("%02d:%02d",$minutes,$seconds);
    }

    return $formatted_time;
}

sub xml {
    my $self = shift;
    return $self->_xml;
}

1;

