package Genome::Individual::View::Solr::Xml;

use strict;
use warnings;

use Genome;

class Genome::Individual::View::Solr::Xml {
    is => 'Genome::View::Solr::Xml',
    has_constant => [
        type => {
            is => 'Text',
            default => 'illumina_run'
        },
        default_aspects => {
            is => 'ARRAY,',
            default => [
                {
                    name => 'common_name',
                    position => 'title',
                },
                {
                    name => 'name',
                    position => 'title',
                },
                {
                    name => 'gender',
                    position => 'content',
                },
                {
                    name => 'upn',
                    position => 'content',
                }
            ]
        },
    ]
};

1;
