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
        display_type => {
            is  => 'Text',
            default => 'Model',
        },
        display_icon_url => {
            is  => 'Text',
            default => 'genome_model_32',
        },
        display_url0 => {
            is => 'Text',
            calculate_from => ['subject'],
            calculate => sub { return join ('?', '/view/genome/model/status.html',$subject->id()); },
        },
        display_label1 => {
            is  => 'Text',
            default => 'last build',
        },
        display_url1 => {
            is  => 'Text',
            calculate_from => ['subject'],
            calculate => sub { 
                my $build = $_[0]->last_succeeded_build();
                return 'none' if !$build;
                return join ('?', '/view/genome/model/build/status.html',$build->id()); 
            },
        },
        display_label2 => {
            is  => 'Text',
        },
        display_url2 => {
            is  => 'Text',
            calculate_from => ['subject'],
            calculate => sub { 
                my $build = $_[0]->last_succeeded_build();
                return 'none' if !$build;
                return join ('/','https://gscweb.gsc.wustl.edu', $build->data_directory());
            },
        },
        display_label3 => {
            is  => 'Text',
            default => 'summary report',
        },
        display_url3 => {
            is  => 'Text',
            calculate_from => ['subject'],
            calculate => sub {
                my $build = $_[0]->last_succeeded_build() || return 'none';
                my $data_dir = join ('?', '/view/genome/model/convergence/build/status.html',$build->id());
                return join('/', 'https://gscweb.gsc.wustl.edu', $data_dir, 'reports', 'Summary', 'report.html');
            },
        },
        default_aspects => {
            is => 'ARRAY',
            default => [
                 {
                    name => 'creation_date',
                    position => 'timestamp',
                },
                {
                    name => 'build_ids',
                    position => 'content',
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
                    name => '__display_name__',
                    position => 'display_title',
                },
            ],
        }
    ]
};

sub display_url {

    my ($self, $i) = @_;
    my $model = $self->subject();
    my $url;

    if ($i == 0) {
        $url = join('?','/view/genome/model/view/status.html',$model->id);
    } elsif ($i == 1) {
        my $build = $model->last_successful_build();
        $url = join('?','/view/genome/model/build/view/status.html',$build->id);
    }

    return $url;
}

#x display_title
#x display_icon_url
#x display_type
#                
#display_label1 
#display_url1
#                
#display_label2
#display_url2
#                
#display_label3
#display_url3


