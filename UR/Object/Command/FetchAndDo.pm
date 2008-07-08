package UR::Object::Command::FetchAndDo;

use strict;
use warnings;

use Command;

class UR::Object::Command::FetchAndDo {
    is => 'Command',
    is_abstract => 1,
    has => [
    subject_class => {
        is => 'UR::Object::Type', 
        id_by => 'subject_class_name',
    }, 
    filter => {
        is => 'Text',  
        is_optional => 1,
        doc => 'Filter results based on the parameters.  See below for how to.'
    },
    ], 
};

use Data::Dumper;

########################################################################

sub help_brief {
    return "Fetch objects based on filters and then perform a function on each object";
}

sub help_synopsis {
    return "Fetch objects based on filters and then perform a function on each object";
}

sub help_detail {          
    my $class = shift;

    return $class->_filter_doc;
}

sub _filter_doc {          
    my $class = shift;

    my $doc = <<EOS;
Filtering:
----------
 Create filter equations by combining filterable properties with operators and values.
 Combine and separate these 'equations' by commas.  
 Use single quotes (') to contain values with spaces: name='genome center'
 Use percent signs (%) as wild cards in like (~).

Filterable Properties: 
EOS

    # Try to get the subject class name
    my $self = $class->create;
    if ( not $self->subject_class_name 
            and my $subject_class_name = $self->_resolved_params_from_get_options->{subject_class_name} ) {
        $self = $class->create(subject_class_name => $subject_class_name);
    }

    if ( $self->subject_class_name ) {
        if ( my @properties = $self->_subject_class_filterable_properties ) {
            for my $property ( @properties ) {
                $doc .= sprintf(" %s\n", $property->property_name);
                next; # TODO doc??
                $doc .= sprintf(
                    " %s: %s\n",
                    $property->property_name,
                    ( $property->description || 'no doc' ),
                );
            }
        }
        else {
            $doc .= sprintf(" Class (%s) does not have any filterable properties.\n", $self->subject_class_name);
        }
    }
    else {
        $doc .= " Need subject class name to get properties.\n"
    }

    $doc .= <<EOS;

Operators:
 =  (exactly equal to)
 ~  (like the value)
 >  (greater than)
 >= (greater than or equal to)
 <  (less than)
 <= (less than or equal to)

Examples:
 name='genome center'
 employees>200
 name~genome%,employees>200
EOS
}

########################################################################

sub execute {  
    my $self = shift;    

    $self->error_message("No subject class name indicated.")
        and return unless $self->subject_class_name;
    
    my $iterator = $self->_fetch
        or return;

    return $self->_do($iterator);
}

sub _subject_class_filterable_properties {
    my $self = shift;

    $self->error_message("No subject_class_name set.")
        and return unless $self->subject_class_name;
    
    return sort { 
        $a->property_name cmp $b->property_name
    } grep {
        $_->column_name ne ''
    } $self->subject_class->get_all_property_objects;
}

sub _fetch
{
    my $self = shift;

    my ($bool_expr, %extra) = UR::BoolExpr->create_from_filter_string(
        $self->subject_class_name, 
        $self->filter, 
    );

    $self->error_message( sprintf('Unrecognized field(s): %s', join(', ', keys %extra)) )
        and return if %extra;
    
    return $self->subject_class_name->create_iterator
    (
        where => $bool_expr,
    ); # error happens in object
}

sub _do
{
    shift->error_message("Abstract class.  Please implement a '_do' method in your subclass.");
    return;
}

1;

=pod

=head1 Name

UR::Object::Command::FetchAndDo

=head1 Synopsis

Base class for fetching objects and then performing a function on/with them.

=head1 Usage

 package MyFecthAndDo;

 use strict;
 use warnings;

 use above "UR";

 class MyFecthAndDo {
     is => 'UR::Object::Command::FetchAndDo',
     has => [
     # other properties...
     ],
 };

 sub _do { # required
    my ($self, $iterator) = @_;

    while (my $obj = $iterator->next) {
        ...
    }

    return 1;
 }
 
 1;

=head1 Provided by the Developer

=head2 _do (required)

Implement this method to 'do' unto the iterator.  Return true for success, false for failure.

 sub _do {
    my ($self, $iterator) = @_;

    while (my $obj = $iterator->next) {
        ...
    }

    return 1;
 }

=head2 subject_class_name (optional)

The subject_class_name is the class for which the objects will be fetched.  It can be specified one of two main ways:

=over

=item I<by_the_end_user_on_the_command_line>

For this do nothing, the end user will have to provide it when the command is run.

=item I<by_the_developer_in the_class_declartion>

For this, in the class declaration, add a has key w/ arrayref of hashrefs.  One of the hashrefs needs to be subject_class_name.  Give it this declaration:

 class MyFetchAndDo {
     is => 'UR::Object::Command::FetchAndDo',
     has => [
         subject_class_name => {
             value => <CLASS NAME>,
             is_constant => 1,
         },
     ],
 };

=back

=head2 helps (optional)

Overwrite the help_brief, help_synopsis and help_detail methods to provide specific help.  If overwiting the help_detail method, use call '_filter_doc' to get the filter documentation and usage to combine with your specific help.

=head1 Disclaimer

Copyright (C) 2005 - 2008 Washington University Genome Sequencing Center

This module is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=head1 Author(s)

B<Eddie Belter> I<ebelter@watson.wustl.edu>

=cut

#$HeadURL$
#$Id$#
