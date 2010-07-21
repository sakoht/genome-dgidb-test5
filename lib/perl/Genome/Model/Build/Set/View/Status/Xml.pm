package Genome::Model::Build::Set::View::Status::Xml;

use strict;
use warnings;

use Genome;

class Genome::Model::Build::Set::View::Status::Xml {
    is => 'Genome::View::Status::Xml',
    has_constant => [
        default_aspects => {
            is => 'ARRAY',
            value => [
                'rule_display',
                {
                    name => 'members',
                    perspective => 'default',
                    toolkit => 'xml',
                    aspects => [
                        'id',
                        'data_directory',
                        'status',
                        'date_scheduled', 
                        'date_completed',
                        {
                            name => 'model',
                            aspects => [
                                'genome_model_id',
                                'name',
                                'subject_id',
                                'subject_class_name',
                                'is_default',
                                'data_directory',
                                'creation_date',
                                'user_name',
                            ],
                            perspective => 'default',
                            toolkit => 'xml',
                            subject_class_name => 'Genome::Model',
                        }
                    ],
                    subject_class_name => 'Genome::Model::Build',
                },
            ]
        }
    ]
};


1;
