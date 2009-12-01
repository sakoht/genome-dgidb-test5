package Genome::Model::Tools::Germline::PrivateSnps;

use strict;
use warnings;

use Genome;


class Genome::Model::Tools::Germline::PrivateSnps {
    is => 'Command',
    has => [
    build_id => {
    },
    build => { is=> 'Genome::Model::Build', id_by => 'build_id' },
    output_file => {
    },
   ],
};

sub help_brief {
    "Germline Tool",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools germline...    
EOS
}

sub help_detail {
    return <<EOS
Germline!!!
EOS
}

sub execute {
    my $self = shift;
    unless($self->build) {
        $self->error_message("Unable to resolve a build object for build id: " . $self->build_id);
        return 0;
    }
    my $db_snp_path = $self->build->resolve_reports_directory() ."/". $self->build->model_id . "variant_filtered_list_files.dbsnp";

    my $filtered_snp_file = $self->build->filtered_snp_file;

    print $filtered_snp_file . "\n";
    print $db_snp_path . "\n";
}
    
        
    

1;

