package Genome::WorkOrder::View::Solr::Xml;

use strict;
use warnings;

use Genome;

class Genome::WorkOrder::View::Solr::Xml {
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
                    name => 'barcode',
                    position => 'content',
                },
                {
                    name => 'name',
                    position => 'content',
                },
                {
                    name => 'pipeline',
                    position => 'content',
                },
                {
                    name => 'project',
                    position => 'content',
                    perspective => 'default',
                    toolkit => 'text',
                    aspects => [
                        'id',
                        'name',
                    ]
                }
        ]
    }
]};

1;
