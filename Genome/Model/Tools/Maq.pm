package Genome::Model::Tools::Maq;

use strict;
use warnings;

use Genome;
use File::Basename;

class Genome::Model::Tools::Maq {
    is => 'Command',
    has => [
        use_version => { is => 'Version', is_optional => 1, default_value => '0.6.3', doc => "Version of maq to use" }
    ],
};

sub sub_command_sort_position { 12 }

sub help_brief {
    "Tools to run maq or work with its output files.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
genome-model tools maq ...    
EOS
}

sub help_detail {                           
    return <<EOS 
More information about the maq suite of tools can be found at http://maq.sourceforege.net.
EOS
}


sub c_linkage_class {
    my $self = shift;
    $DB::single = $DB::stopper;

    my $version = $self->use_version;
    $version =~ s/\./_/g;

    my $class_to_use = __PACKAGE__ . "::CLinkage$version";
    
    #eval "use above '$class_to_use';";
    eval "use $class_to_use;";
    if ($@) {
        $self->error_message("Failed to use $class_to_use: $@");
        return undef;
    }

    return $class_to_use;
}

sub maq_path {
    my $self = $_[0];
    return $self->path_for_maq_version($self->use_version);
}

sub path_for_maq_version {
    my $class = shift;
    my $version = shift;
    if ($version eq '0.6.3') {
        return '/gsc/pkg/bio/maq/maq-0.6.3_x86_64-linux/maq';
    } elsif ($version eq '0.6.4') {
        return '/gsc/pkg/bio/maq/maq-0.6.4_x86_64-linux/maq';
    } elsif ($version eq '0.6.5') {
        return '/gsc/pkg/bio/maq/maq-0.6.5_x86_64-linux/maq';
    } elsif ($version eq '0.6.8') {
        return '/gsc/pkg/bio/maq/maq-0.6.8_x86_64-linux/maq';
    } elsif ($version eq '0.7.1') {
        return '/gsc/pkg/bio/maq/maq-0.7.1-64/bin/maq';     
    } elsif ($version eq 'maq') {
        return 'maq';
    } else {
        return;
    }
}

sub path_for_mapsplit_version {
    my $class = shift;
    my $version = shift;
    if ($version eq '0.6.3') {
        return '/gscuser/charris/c-src-BLECH/mapsplit/mapsplit';
    } elsif ($version eq '0.6.4') {
        return '/gscuser/charris/c-src-BLECH/mapsplit/mapsplit';
    } elsif ($version eq '0.6.5') {
        return '/gscuser/charris/c-src-BLECH/mapsplit/mapsplit';
    } elsif ($version eq '0.6.8') {
        return '/gscuser/charris/c-src-BLECH/mapsplit/mapsplit';
    } elsif ($version eq '0.7.1') {
        return '/gscuser/charris/c-src-BLECH/mapsplit/mapsplit_long';
    } elsif ($version eq 'maq') {
        return;
    } else {
        return;
    }
}

1;

