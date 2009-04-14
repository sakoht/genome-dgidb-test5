package Genome::Config;

use strict;
use warnings;

sub user_email {
    my $self = shift;
    my $user = shift;
    $user ||= $ENV{USER};
    return $user . '@genome.wustl.edu';
}

# operating directories

sub root_directory {
    $ENV{GENOME_MODEL_ROOT} || '/gscmnt/839/info/medseq';
}

sub data_directory {
     $ENV{GENOME_MODEL_DATA} || '/gscmnt/sata363/info/medseq';
}

# links

sub model_links_directory {
    return shift->root_directory . '/model_links';
}

sub alignment_links_directory {
    return shift->root_directory . '/alignment_links';
}

sub model_comparison_link_directory {
    return shift->root_directory . '/model_comparison_links';
}

# data

sub model_data_directory {
    my $self = shift;
    if (defined($ENV{'GENOME_MODEL_TESTDIR'}) &&
        -e $ENV{'GENOME_MODEL_TESTDIR'}
    ) {
            return $ENV{'GENOME_MODEL_TESTDIR'};
    } else {
            return $self->data_directory .'/model_data';
    }   
}

sub alignment_data_directory {
    return shift->data_directory . '/alignment_data';
}

sub model_comparison_data_directory {
    return shift->data_directory . '/model_comparison_data';
}

# reflection of the different types of models, and their related processing profiles and builds

sub type_names {
    return 
        map { s/\-/ /g; $_ }
        map { Command->_command_name_for_class_word($_) }
        map { s/^Genome\::Model:://; $_ } 
        shift->model_subclass_names;
}

my $use_model_subclasses = 0;
sub _use_model_subclasses {
    # We follow a naming convention which allows us to dynamically list all sub-classes of model.
    # There is some flexibility loss by enforcing the naming convention, but the benefit is reflection.
    # A different config could make a different choice if necessary...
    
    unless ($use_model_subclasses) {
        require Genome::Model;
        my $path = $INC{'Genome/Model.pm'};
        unless ($path) {
            die "failed to find the path for Genome/Model.pm in %INC???";
        }
        $path =~ s/.pm\s*$// or die "no pm on $path?";
        unless (-d $path) {
            die "$path is not a directory?";
        }
        my @possible_subclass_modules = glob("$path/*.pm");
        for my $possible_module (@possible_subclass_modules) {
            my $class = $possible_module;
            $class =~ s/.pm$//;
            $class =~ s/\//\:\:/g;
            $class =~ s/^.*(Genome::Model::[^\:]+)/$1/;
            eval "use $class";
            die "Error using module $class ($possible_module): $@" if $@;
            unless ($class->isa("Genome::Model")) {
                next;
            }
            my $suffix = $class;
            $suffix =~ s/^Genome\::Model:://;
            #$model_subclass_names, $class;
        }
        $use_model_subclasses = 1;
    }
    return 1;
}


=pod

=head1 NAME

Genome::Config - environmental configuration for the genome modeling tools

=head1 DESCRIPTION

This module currently just contains global, hard-coded paths.

For portability, it should use an instance of Genome::Config loadable from an environment variable.

=head1 METHODS

=head2 root_directory 

This is the directory under which all other data is symlinked.
It can be changed with the GENOME_MODEL_ROOT environment variable.

This value is typically constant for one site.  It changes only for testing.

=head2 data_directory 

This is the directory under which new data is actually placed.
It can be changed with the GENOME_MODEL_DATA environment variable.

This value changes over time, as disk fills, and new space is made for
new data.

=head2 model_links_directory

All models directories are given a symlink under this directory.  The symlink 
uses the model's "name".

By default the $root_directory/model_links.

=head2 model_data_directory

The default directory into which new models are placed.  Builds go into 
sub-directories here unless otherwise specified.

By default the $data_directory/model_data.

=head2 alignment_links_directory

All alignment linked under this directory.

By default the $root_directory/alignment_links.

=head2 alignment_data_directory

New alignment data is stored or under this directory.

By default the $data_directory/alignment_data.

=head2 comparison_links_directory

Cross-model comparisons are linked here.

By default $current_links_directory/model_comparisons.

=head2 comparison_data_directory

New cross-model comparisons are stored here.

By default $data_directory/model_comparisons.

=cut

1;

