package Genome::Model::View::Solr::Xml;

use strict;
use warnings;

use Genome;

class Genome::Model::View::Solr::Xml {
    is => 'Genome::View::Solr::Xml',
    has_constant => [
        type => {
            is => 'Text',
            default => 'model'
        },
        default_aspects => {
            is => 'ARRAY',
            default => [
                {
                    name => 'creation_date',
                    position => 'timestamp',
                },
                {
                    name => 'processing_profile',
                    position => 'content',
                    perspective => 'default',
                    toolkit => 'text',
                    aspects => [
                        'id',
                        'name'
                    ]
                },
                {
                    name => 'data_directory',
                    position => 'content',
                },
                {
                    name => 'instrument_data',
                    position => 'content',
                    perspective => 'default',
                    toolkit => 'text',
                    aspects => [
                        'id',
                        'run_name',
                    ]
                }
            ],
        }
    ]
};

1;
