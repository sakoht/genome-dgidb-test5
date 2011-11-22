package Genome::Model::Tools::ChimeraSlayer::DetectChimeras;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
use File::Basename;

class Genome::Model::Tools::ChimeraSlayer::DetectChimeras {
    is => 'Command::V2',
    has => [
        sequences => {
            is => 'Text',
            doc => 'sequence to run',
        },
        nastier_params => {
            is => 'Text',
            doc => 'String of params to pass to nastier',
            is_optional => 1,
        },
        chimera_slayer_params => {
            is => 'Text',
            doc => 'String of params to pass to chimera-slayer',
            is_optional => 1,
        },
        chimeras => {
            is => 'Text',
            doc => 'ChimeraSlayer output file that contains chimeras',
            is_mutable => 1,
            is_optional => 1,
        },
    ],
};

sub help_brief {
    return 'Run nastier then with the output run chimera slayer .. for details on each, try gmt nastier --h and gmt chimera-slayer --h',
}

sub help_detail {
    return <<"EOS"
This command takes a sequences file and runs nastier then uses the nastier output file to run chimera slayer
EOS
}

sub execute {
    my $self = shift;
    
    unless ( -s $self->sequences ) {
        $self->error_message("Failed to find sequences file or file is zero size: ".$self->sequences );
        return;
    }
    #build nastier/chimeraSlayer params
    my %nastier_params;
    if ( not %nastier_params = $self->build_nastier_params ) {
        $self->error_message("Failed to build nastier params");
        return;
    }
    my %chimera_slayer_params;
    if ( not %chimera_slayer_params = $self->build_chimera_slayer_params ) {
        $self->error_message("Failed to build chimera slayer params");
        return;
    }

    #validate/create params/class
    my $n_class = Genome::Model::Tools::Nastier->create( %nastier_params );
    if ( not $n_class ) {
        $self->error_message("Failed to create Nastier class using param: ".$self->nastier_params);
        return;
    }
    my $cs_class = Genome::Model::Tools::ChimeraSlayer->create( %chimera_slayer_params );
    if ( not $cs_class ) {
        $self->error_message("Failed to create ChimeraSlayer class using param: ".$self->chimera_slayer_params);
        return;
    }

    #execute
    if ( not $n_class->execute ) {
        $self->error_message("Failed to execute Nastier using params: ".$self->nastier_params);
        return;
    }
    $self->status_message("Finished running nastier");
    if ( not $cs_class->execute ) {
        $self->error_message("Failed to execute ChimeraSlayer using param: ".$self->chimera_slayer_params);
        return;
    }
    $self->status_message("Finished running chimera slayer");

    #check output
    $self->chimeras( $self->sequences.'.out.CPS.CPC' );
    if ( not -s $self->chimeras ) {
        $self->error_message("Failed to find chimera slayer output file or file is empty: ".$self->chimeras);
        return;
    }

    return 1;
}

sub build_nastier_params {
    my $self = shift;

    my %params;
    if ( $self->nastier_params ) {
        %params = Genome::Utility::Text::param_string_to_hash( $self->nastier_params );
        if ( $params{query_FASTA} ) {
            $self->status_message("query_FASTA for nastier will be automatically set by this program");
            delete $params{query_FASTA};
        }
        if ( $params{output_file} ) {
            $self->status_message("output_file for nastier will be automatically set by this program");
            delete $params{output_file};
        }
    }

    $params{query_FASTA} = $self->sequences;
    $params{output_file} = $self->sequences.'.out';
    #print Dumper \%params;

    return %params;
}

sub build_chimera_slayer_params {
    my $self = shift;

    my %params;
    if ( $self->chimera_slayer_params ) {
        %params = Genome::Utility::Text::param_string_to_hash( $self->chimera_slayer_params );
        if ( $params{exec_dir} ) {
            $self->status_message("exec_dir for ChimeraSlayer will be automatically set by this program");
            delete $params{exec_dir};
        }
        if ( $params{query_NAST} ) {
            $self->status_message("query_NAST for ChimeraSlayer will be automatically set by this program");
            delete $params{query_NAST};
        }
    }

    $params{query_NAST} = $self->sequences.'.out';
    $params{exec_dir} = dirname( $self->sequences );
    #print Dumper \%params;

    return %params;
}

1;

