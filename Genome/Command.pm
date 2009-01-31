package Genome::Command;

use strict;
use warnings;

use Genome;

use Data::Dumper;
require File::Basename;

class Genome::Command {
    is => 'Command',
};
         
my @SUB_COMMANDS = qw/
    project    
    taxon
    population-group     
    individual        
    sample     
    library
    instrument-data       
    processing-profile     
    model                  
    tools                  
/;

our %SUB_COMMAND_CLASSES = 
    map {
        my @words = split(/-/,$_);
        my $class = join("::",
            'Genome',
            join('',map{ ucfirst($_) } @words),
            'Command'
        );
        ($_ => $class);
    }
    @SUB_COMMANDS;

$SUB_COMMAND_CLASSES{'tools'} = 'Genome::Model::Tools';

our @SUB_COMMAND_CLASSES = map { $SUB_COMMAND_CLASSES{$_} } @SUB_COMMANDS;

for my $class ( @SUB_COMMAND_CLASSES ) {
    eval("use $class;");
    die $@ if $@; 
}

#< Command Naming >#
sub command_name {
    my $class = ref($_[0]) || $_[0];
    return $class->SUPER::command_name unless $class eq __PACKAGE__;
    return 'genome';
}

sub command_name_brief {
    my $class = ref($_[0]) || $_[0];
    return $class->SUPER::command_name_brief unless $class eq __PACKAGE__;
    return 'genome';
}

#< Sub Command Stuff >#
sub is_sub_command_delegator {
    return 1;
}

sub sorted_sub_command_classes {
    return @SUB_COMMAND_CLASSES;
}

sub sub_command_classes {
    return @SUB_COMMAND_CLASSES;
}

sub class_for_sub_command {
    my $class = ref($_[0]) || $_[0];
    return $class->SUPER::class_for_sub_command unless $class eq __PACKAGE__;
    return $SUB_COMMAND_CLASSES{$_[1]};
}

1;

#$HeadURL$
#$Id$

