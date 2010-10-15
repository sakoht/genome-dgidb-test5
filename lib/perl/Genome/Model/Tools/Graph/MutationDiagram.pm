package Genome::Model::Tools::Graph::MutationDiagram;

use strict;
use warnings;

use Genome;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram;

class Genome::Model::Tools::Graph::MutationDiagram {
    is => 'Command',
    has => [
        maf => { 
            type => 'String',  
            doc => "MAF file", 
            is_optional => 1,
        },
        annotation => {
            type => 'String',
            doc => "Annotator output",
            is_optional => 1,
        },
        genes   => { 
            type => 'String',  
            doc => "comma separated list of (hugo) gene names (uppercase)--default is ALL", 
            is_optional => 1
        },
        custom_domains   => { 
            type => 'String',  
            doc => "comma separated list of protein domains to add. Expects triplets of name,start,end.", 
            is_optional => 1
        },

    ],
};

sub help_brief {
    "report mutations as a (svg) diagram"
}

sub help_synopsis {
    return <<"EOS"
gmr graph mutation-diagram  --annotation my.maf
EOS
}

sub help_detail {
    return <<"EOS"
Generates (gene) mutation diagrams from an annotation file.
EOS
}

sub execute {
    $DB::single = $DB::stopper;
    my $self = shift;
    my $maf_file = $self->maf;
    my $anno_file = $self->annotation;
    if($maf_file) {
        my $maf_obj = new Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram(
            maf_file => $maf_file,
            hugos => $self->genes,
            custom_domains => $self->custom_domains,
        );
    }
    elsif($anno_file) {
        my $anno_obj = new Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram(
            annotation => $anno_file,
            hugos => $self->genes,
            custom_domains => $self->custom_domains,
        );
    }
    else {
        #must have one or the other
        $self->error_message("Must provide either maf or annotation output format");
        return;
    }
    return 1;
}


1;

#$HeadURL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/Genome/Model/ReferenceAlignment/Report/MutationDiagram.pm $
#$Id: MutationDiagram.pm 53299 2009-11-20 22:45:10Z eclark $
