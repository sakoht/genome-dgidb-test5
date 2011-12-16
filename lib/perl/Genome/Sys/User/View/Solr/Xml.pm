package Genome::Sys::User::View::Solr::Xml;

use strict;
use warnings;

use Genome;

class Genome::Sys::User::View::Solr::Xml {
    is => 'Genome::View::Solr::Xml',
    has => [
        type => {
            is => 'Text',
            default => 'user'
        },
        display_type => {
            is  => 'Text',
            default => 'User',
        },
        display_icon_url => {
            is  => 'Text',
            default => 'genome_sys_user_16',
        },
        display_url0 => {
            is => 'Text',
            calculate_from => ['subject'],
            calculate => sub { return join ('?id=', '/view/genome/sys/user/status.html',$_[0]->email()); },
        },
        display_label1 => {
            is  => 'Text',
            default => 'send mail',
        },
        display_url1 => {
            is  => 'Text',
            calculate_from => ['subject'],
            calculate => sub { return 'mailto:' . $_[0]->email(); },
        },
        display_label2 => {
            is  => 'Text',
            default => 'wiki',
        },
        display_url2 => {
            is  => 'Text',
            calculate_from => ['subject'],
            calculate => sub { return 'https://gscweb.gsc.wustl.edu/wiki/User:' . $_[0]->username(); },
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
                    name => 'name',
                    position => 'content',
                },
                {
                    name => 'email',
                    position => 'content',
                },
                {
                    name => 'name',
                    position => 'display_title',
                },
            ],
        }
    ]
};

1;
