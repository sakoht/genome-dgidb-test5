package Genome::Model::Tools;

use strict;
use warnings;
use Genome;

our $VERSION = $Genome::VERSION;

class Genome::Model::Tools {
    is => 'Command',
    doc => 'bioinformatics tools for genomics'
};

sub command_name { 'gmt' }


1;

=pod

=head1 NAME

Genome::Model::Tools - the base namespace for B<gmt> tool modules

=head1 DESCRIPTION

Modules with names starting with Genome::Model::Tools are directly invokable by
the "gmt" command, installed with the core Genome package.

These modules all inherit from Command and use UR for their class definitions.

=over 4

=item

Copy the Example1.pm.template to Example1.pm and try "gmt" in the same directory
for an example tool.  

=item

See B<Command> for details on how to write commands.

=item

See B<UR> for details on writing UR classes in general.

=back

=head1 AUTHORS

This software is developed by the analysis and engineering teams at 
The Genome Center at Washington Univiersity in St. Louis, with funding from 
the National Human Genome Research Institute.

=head1 LICENSE

This software is copyright Washington University in St. Louis.  It is released under
the Lesser GNU Public License (LGPL) version 3.  See the associated LICENSE file in
this distribution.

=head1 BUGS

For defects with any software in the genome namespace,
contact genome-dev@genome.wustl.edu.

=head1 SEE ALSO

B<gmt>, B<Genome>

=cut

