package Genome::Library::View::Solr::Xml;

use strict;
use warnings;

use Genome;

class Genome::Library::View::Solr::Xml {
    is => 'Genome::View::Solr::Xml',
    has_constant => [
        type => {
            is => 'Text',
            default => 'library'
        },
        display_type => {
            is  => 'Text',
            default => 'Library',
        },
        display_icon => {
            is  => 'Text',
            default => 'genome_library_32.png',
        },
        display_url0 => {
            is => 'Text',
            calculate_from => ['subject'],
            calculate => sub { return join ('?', '/view/genome/library/status.html',$_[0]->id()); },
        },
        display_label1 => {
            is  => 'Text',
        },
        display_url1 => {
            is  => 'Text',
        },
        display_label2 => {
            is  => 'Text',
        },
        display_url2 => {
            is  => 'Text',
        },
        display_label3 => {
            is  => 'Text',
        },
        display_url3 => {
            is  => 'Text',
        },
        default_aspects => {
            is => 'ARRAY',
            default => [
                {
                    name => 'sample_name',
                    position => 'content',
                },
                {
                    name => 'species_name',
                    position => 'content',
                },
                {
                    name => '__display_name__',
                    position => 'display_title',
                },
            ],
        }
    ]
};

1;
