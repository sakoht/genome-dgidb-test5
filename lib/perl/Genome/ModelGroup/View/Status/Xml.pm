package Genome::ModelGroup::View::Status::Xml;

use strict;
use warnings;
use Genome;
use Data::Dumper;
use XML::LibXML;

class Genome::ModelGroup::View::Status::Xml {
    is => 'UR::Object::View::Default::Xml',
    has_constant => [
        default_aspects => {
            is => 'ARRAY',
            default => [
                'id',
                'name',
                {
                    name => 'models',
                    perspective => 'default',
                    toolkit => 'xml',
                    aspects => [
                        'genome_model_id',
                        'name',
                        'subject_id',
                        'subject_class_name',
                        'is_default',
                        'data_directory',
                        {
                            name => 'processing_profile',
                            aspects => ['id', 'name'],
                            perspective => 'default',
                            toolkit => 'xml'
                        },
                        'creation_date',
                        'user_name',
                        {
                            name => 'builds',
                            aspects => [
                                'id', 'data_directory', 'status', 'date_scheduled', 'date_completed',
                            ],
                            perspective => 'default',
                            toolkit => 'xml',
                            subject_class_name => 'Genome::Model::Build',
                        },
                        'region_of_interest_set_name',
                    ],
                    subject_class_name => 'Genome::Model',
                },
                {
                    name => 'convergence_model',
                    aspects => [
                        'id',
                        'name',
                        {
                            name => 'last_complete_build',
                            aspects => [
                                'id', 'data_directory'
                            ],
                            perspective => 'default',
                            toolkit => 'xml',
                            subject_class_name => 'Genome::Model::Build',
                        }
                    ],
                    perspective => 'default',
                    toolkit => 'xml',
                },
            ]
        }
    ]
};

1;

=pod

=head1 NAME

Genome::ModelGroup::View::Status::XML - status summary for a model group in XML format

=head1 SYNOPSIS

$i = Genome::ModelGroup->get(1234);
$v = Genome::ModelGroup::View::Status::Xml->create(subject => $i);
$xml = $v->content;

=head1 DESCRIPTION

This view renders the summary of an model group's status in XML format.

=cut

