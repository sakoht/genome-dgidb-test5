package Genome::Subject::Set::View::Create::Html;

use strict;
use warnings;
require UR;

class Genome::Subject::Set::View::Create::Html {
    is => 'Genome::View::Static::Html',
    has_constant => [
        toolkit     => { value => 'html' },
        perspective => { value => 'create' },
        desired_perspective => { value => 'status' },
    ],
};

sub _title {
    return 'Upload Subject Data';
}

sub _html_body {
    return Genome::Sys->read_file(__FILE__ .'.html');
}

1;
