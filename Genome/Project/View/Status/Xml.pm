package Genome::Project::View::Status::Xml;

use strict;
use warnings;

use Genome;

class Genome::Project::View::Status::Xml {
    is => 'Genome::View::Status::Xml',
    has_constant => [
        default_aspects => {
            is => 'ARRAY',
            value => [
                'id',
                'name',
                'status',
                'description',
                'project_type',
                'mailing_list',
                {
                    name => 'external_contact',
                    perspective => 'default',
                    toolkit => 'xml',
                    aspects => [
                        'id',
                        'email',
                        'name',
                        'type',
                    ]
                },
                {
                    name => 'internal_contact',
                    perspective => 'default',
                    toolkit => 'xml',
                    aspects => [
                        'id',
                        'email',
                        'name',
                        'type',
                    ]
                },
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
                            name => 'last_succeeded_build',
                            aspects => [
                                'id', 'data_directory'
                            ],
                            perspective => 'default',
                            toolkit => 'xml',
                            subject_class_name => 'Genome::Model::Build',
                        }
                    ],
                },
                {
                    name => 'samples',
                    perspective => 'default',
                    toolkit => 'xml',
                    aspects => [
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
                                    name => 'last_succeeded_build',
                                    aspects => [
                                        'id', 'data_directory'
                                    ],
                                    perspective => 'default',
                                    toolkit => 'xml',
                                    subject_class_name => 'Genome::Model::Build',
                                }
                            ],
                            subject_class_name => 'Genome::Model',
                        }
                    ]
                },
            ]
        }
    ]
};


1;
