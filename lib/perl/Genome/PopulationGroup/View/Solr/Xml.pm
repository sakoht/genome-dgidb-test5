package Genome::PopulationGroup::View::Solr::Xml;

use strict;
use warnings;

use Genome;

class Genome::PopulationGroup::View::Solr::Xml {
    is => 'Genome::View::Solr::Xml',
    has_constant => [
        type => {
            is => 'Text',
            default => 'population_group'
        },
        display_type => {
            is  => 'Text',
            default => 'Population',
        },
        display_icon_url => {
            is  => 'Text',
            default => 'genome_population_32.png',
        },
        display_url0 => {
            is => 'Text',
            calculate_from => ['subject'],
            calculate => sub { return join ('?', '/view/genome/population/status.html',$_[0]->id()); },
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
                    name => 'description',
                    position => 'content',
                },
                {
                    name => 'members',
                    position => 'content',
                    perspective => 'default',
                    toolkit => 'text',
                    aspects => [ 'name' ]
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
