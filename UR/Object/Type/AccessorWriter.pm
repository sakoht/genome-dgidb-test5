
package UR::Object::Type::AccessorWriter;

package UR::Object::Type;

use strict;
use warnings;
#use warnings FATAL => 'all';

use Carp ();
use Sub::Name ();
use Sub::Install ();

sub construct_class_from_data
{
    my $self = shift;

    my %params = @_;
    my $class_name = $params{"class_name"};
    my @id_properties = @{ $params{id_properties} };
    my @other_properties = @{ $params{other_properties} };
    my @class_properties = ($params{class_properties} ? @{ $params{class_properties} } : ());

    for my $property (@id_properties)
    {
        UR::Object::Type->mk_ro_accessor($class_name,$property,uc($property));
    }

    for my $property (@other_properties)
    {
        UR::Object::Type->mk_rw_accessor($class_name,$property,uc($property));
    }

    for my $property (@class_properties)
    {
        UR::Object::Type->mk_class_accessor($class_name,$property);
    }

    my $props = [@id_properties, @other_properties];
    my $cols = [map { uc($_) } @$props];

    no strict 'refs';

    my @isa = @{$class_name . '::ISA'};
    for my $base (@isa) {
        my $isl = ${$base . '::immediate_subclasses_loaded'} ||= [];
        push @$isl, $class_name;
        $isl = ${$base . '::Ghost::immediate_subclasses_loaded'} ||= [];
        push @$isl, $class_name . '::Ghost';
    }

}

sub mk_rw_accessor {
    my ($self, $class_name, $accessor_name, $column_name, $property_name, $is_transient) = @_;
    $property_name ||= $accessor_name;

    my $full_name = join( '::', $class_name, $accessor_name );
    my $accessor = Sub::Name::subname $full_name => sub {
        if (@_ > 1) {
            my $old = $_[0]->{ $property_name };
            my $new = $_[1];

            # The accessors may compare undef and an empty
            # string.  For speed, we turn warnings off rather
            # than add extra code to make the warning disappear.
            no warnings;

            if ($old ne $new)
            {
                $_[0]->{ $property_name } = $new;
                $_[0]->signal_change( $accessor_name, $old, $new ) unless $is_transient; # FIXME is $is_transient right here?  Maybe is_volitile instead (if at all)?
            }
            return $new;
        }
        return $_[0]->{ $property_name };  # FIXME what to do about properties with default_values?
    };

    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $accessor_name,
        code => $accessor,
    });

    #$column_name = uc($column_name);

    if ($column_name)
    {
        Sub::Install::reinstall_sub({
            into => $class_name,
            as   => $column_name,
            code => $accessor,
        });

        # These are for backward-compatability with old modules.  Remove asap.
        no strict 'refs';

        ${$class_name . '::column_for_property'}
            {$property_name} = $column_name;

        ${$class_name . '::property_for_column'}
            {$property_name} = $accessor_name;
    }
}

sub mk_ro_accessor {
    my ($self, $class_name, $accessor_name, $column_name, $property_name) = @_;
    $property_name ||= $accessor_name;

    my $full_name = join( '::', $class_name, $accessor_name );
    my $accessor = Sub::Name::subname $full_name => sub {
        if (@_ > 1) {
            my $old = $_[0]->{ $property_name};
            my $new = $_[1];

            no warnings;

            if ($old ne $new)
            {
                Carp::confess("Cannot change read-only property $accessor_name for class $class_name!"
                . "  Failed to update " . $_[0]->display_name_full . " property: $property_name from $old to $new");
            }
            return $new;
        }
        return $_[0]->{ $property_name };
    };

    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $accessor_name,
        code => $accessor,
    });

    $column_name = uc($column_name);
    
    if ($column_name)
    {
        Sub::Install::reinstall_sub({
            into => $class_name,
            as   => $column_name,
            code => $accessor,
        });

        # These are for backward-compatability with old modules.  Remove asap.
        no strict 'refs';

        ${$class_name . '::column_for_property'}
            {$property_name} = $column_name;

        ${$class_name . '::property_for_column'}
            {$property_name} = $accessor_name;
    }
}


# FIXME - this is kinda ugly.  I've co-opted this to work for is_many with id_by where the thing
# we're id-ing_by is an ARRAY.  This case should probably be broken out to make something like mk_object_set_accessors,
# or change mk_object_set_accessors to support this
sub mk_id_based_object_accessor {
    my ($self, $class_name, $accessor_name, $id_by, $r_class_name, $where) = @_;

    unless (ref($id_by)) {
        $id_by = [ $id_by ];
    }

    my $id_resolver;
    my $id_decomposer;
    my @id;
    my $id;
    my $full_name = join( '::', $class_name, $accessor_name );
    my $accessor = Sub::Name::subname $full_name => sub {
        my $self = shift;
        if (@_ == 1) {
            # This one is to support syntax like this
            # $cd->artist($different_artist);
            # to switch which artist object this cd points to
            my $object_value = shift;
            $id_decomposer ||= $r_class_name->get_class_object->get_composite_id_decomposer;
            @id = ( defined($object_value) ? $id_decomposer->($object_value->id) : () );
            for my $id_property_name (@$id_by) {
                $self->$id_property_name(shift @id);
            }
            return $object_value;
        }
        else {
            $id_resolver ||= $r_class_name->get_class_object->get_composite_id_resolver;
            @id = map { $self->$_ } @$id_by;
            $id = $id_resolver->(@id);
            return if not defined $id;
            if (@_ || $where) { 
                # There were additional params passed in 
                return $r_class_name->get(id => $id, @_, @$where);
            } else {
                return $r_class_name->get($id);
            }
        }
    };

    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $accessor_name,
        code => $accessor,
    });
}

sub mk_indirect_ro_accessor {
    my ($self, $class_name, $accessor_name, $via, $to, $where) = @_;
    my @where = ($where ? @$where : ());
    my $full_name = join( '::', $class_name, $accessor_name );
    my $filterable_accessor_name = 'get_' . $accessor_name;
    my $filterable_full_name = join( '::', $class_name, $filterable_accessor_name );

    my $accessor = Sub::Name::subname $full_name => sub {
        my $self = shift;
        Carp::confess("assignment value passed to read-only indirect accessor $accessor_name for class $class_name!") if @_;
        my @bridges = $self->$via(@where);
        return unless @bridges;
        my @results = map { $_->$to } @bridges;
        $self->context_return(@results); 
    };

    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $accessor_name,
        code => $accessor,
    });

    my $r_class_name;
    my $r_class_name_resolver = sub {
        return $r_class_name if $r_class_name;

        my $linking_property = UR::Object::Property->get(class_name => $class_name, property_name => $via);
        unless ($linking_property->data_type) {
            die "Property ${class_name}::${accessor_name}: via refers to a property with no data_type.  Can't process filter";
        }
        my $final_property = UR::Object::Property->get(class_name => $linking_property->data_type, 
                                                       property_name => $to);
        unless ($final_property->data_type) {
            die "Property ${class_name}::${accessor_name}: to refers to a property with no data_type.  Can't process filter";
        }
        $r_class_name = $final_property->data_type;
    };

    my $filterable_accessor = Sub::Name::subname $filterable_full_name => sub {
        my $self = shift;
        #my @results = $accessor->($self);
        my @results = $self->$accessor_name();
        if (@_) {
            my $rule;
            if (@_ == 1 and ref($_[0]) and $_[0]->isa('UR::BoolExpr')) {
                $rule = shift;
            } else {
                $r_class_name ||= $r_class_name_resolver->();
                $rule = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($r_class_name, @_);
            }
            @results = grep { $rule->evaluate($_) } @results;
        }
        $self->context_return(@results);
    };
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $filterable_accessor_name,
        code => $filterable_accessor,
    });

}


sub mk_indirect_rw_accessor {
    my ($self, $class_name, $accessor_name, $via, $to, $where, $singular_name) = @_;
    my @where = ($where ? @$where : ());
    my $full_name = join( '::', $class_name, $accessor_name );
    
    my $update_strategy; # defined the first time we "set" a value through this
    my $adder;
    my $via_property_meta;
    my $r_class_name;

    my $resolve_update_strategy = sub {
        unless (defined $update_strategy) {
            # Resolve the strategy.  We need to figure out if $to 
            # refers to an id-property.  This is only called once, when the
            # accessor is first used.
        
            # If we reference a remote object, and go to one of its id properties
            # we must do a delete/create instead of property change.  Note that
            # this is only allowed when the remote object has no direct properties
            # which are not id properties.
        
            $via_property_meta ||= $class_name->get_class_object->get_property_meta_by_name($via);
            unless ($via_property_meta) {
                $via_property_meta = $class_name->get_class_object->get_property_meta_by_name($via);
                die "no meta for $via in $class_name!?" unless $via_property_meta;
            }
            $adder = "add_" . $via_property_meta->singular_name;
            $r_class_name ||= $via_property_meta->data_type;
            my @r_id_property_names = $r_class_name->get_class_object->id_property_names;
            if (grep { $_ eq $to } @r_id_property_names) {
                $update_strategy = 'delete-create'
            }
            else {
                $update_strategy = 'change';
            }
        }
        return $update_strategy;
    };
 
    my $accessor = Sub::Name::subname $full_name => sub {
        my $self = shift;
        my @bridges = $self->$via(@where);
        if (@_) {            
            $resolve_update_strategy->() unless (defined $update_strategy);

            if ($update_strategy eq 'change') {
                if (@bridges == 0) {
                    #print "adding via $adder @where :::> $to @_\n";
                    @bridges = $self->$adder(@where, $to => $_[0]);
                    #WAS > Carp::confess("Cannot set $accessor_name on $class_name $self->{id}: property is via $via which is not set!");
                }
                elsif (@bridges > 1) {
                    Carp::confess("Cannot set $accessor_name on $class_name $self->{id}: multiple instances of '$via' found, via which the property is set!");
                }
                #print "updating $bridges[0] $to to @_\n";
                return $bridges[0]->$to(@_);
            }
            elsif ($update_strategy eq 'delete-create') {
                if (@bridges > 1) {
                    Carp::confess("Cannot set $accessor_name on $class_name $self->{id}: multiple instances of '$via' found, via which the property is set!");
                }
                else {
                    if (@bridges) {
                        #print "deleting $bridges[0]\n";
                        $bridges[0]->delete;
                    }
                    #print "adding via $adder @where :::> $to @_\n";
                    @bridges = $self->$adder(@where, $to => $_[0]);
                    unless (@bridges) {
                        Carp::confess("Failed to add bridge for $accessor_name on $class_name $self->{id}: property is via $via!");
                    }
                }
            }
        }
        return unless @bridges;
        my @results = map { $_->$to } @bridges;
        $self->context_return(@results); 
    };

    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $accessor_name,
        code => $accessor,
    });

    if ($singular_name) {  # True if we're defining an is_many indirect property
        my $via_adder;

        my $add_accessor = Sub::Name::subname $class_name ."::add_$singular_name" => sub {
            my($self,$value) = @_;

            $resolve_update_strategy->() unless (defined $update_strategy);
            unless (defined $via_adder) {
                $via_adder = "add_" . $via_property_meta->singular_name;
            }
           
            $self->$via_adder(@where, $to => $value);
        };

        Sub::Install::reinstall_sub({
            into => $class_name,
            as   => "add_$singular_name",
            code => $add_accessor,
        });
    }
    
}


sub mk_calculation_accessor {
    my ($self, $class_name, $accessor_name, $calculation_src, $calculate_from, $params, $is_constant) = @_;

    my $accessor;
    my @src;

    if (not defined $calculation_src or $calculation_src eq '') {
        $accessor = \&{ $class_name . '::' . $accessor_name };
        unless ($accessor) {
            die "$accessor_name not defined in $class_name!  Define it, or specify a calculate => sub{} or calculate => \$perl_src in the class definition.";
        }
    }
    elsif (ref($calculation_src) eq 'CODE') {
        $accessor = sub {
            my $self = shift;
            if (@_) {
                Carp::confess("$class_name $accessor_name is a read-only property derived from @$calculate_from");
            }
            return $calculation_src->(map { $self->$_ } @$calculate_from);        
        };
    }
    elsif ($calculation_src =~ /^[^\:\W]+$/) {
        # built-in formula
        my $module_name = "UR::Object::Type::AccessorWriter::" . ucfirst(lc($calculation_src));
        eval "use $module_name";
        die $@ if $@;
        @src = ( 
            "sub ${class_name}::${accessor_name} {",
            'my $self = $_[0];',
            "${module_name}->calculate(\$self, [" . join(",", map { "'$_'" } @$calculate_from) . "], \@_)",
            '}'
        );
    }
    elsif($is_constant) {
        # memoize on a per-object basis
        @src = ( 
            "sub ${class_name}::${accessor_name} {",
            'my $self = $_[0];',
            "return \$self->{$accessor_name} if exists \$self->{$accessor_name};",
            (map { "my \$$_ = \$self->$_;" } @$calculate_from),
            "\$self->{$accessor_name} = eval {",
            $calculation_src,
            "};",
            'die $@ if $@;',
            "return \$self->{$accessor_name};",
            '}'
        );
    }    
    else {
        @src = ( 
            "sub ${class_name}::${accessor_name} {",
            ($params ? 'my ($self,%params) = @_;' : 'my $self = $_[0];'),
            (map { "my \$$_ = \$self->$_;" } @$calculate_from),
            ($params ? (map { "my \$$_ = delete \$params{'$_'};" } @$params) : ()),
            $calculation_src,
            '}'
        );
    }

    if ($accessor) {
        my $full_name = join( '::', $class_name, $accessor_name );
        $accessor = Sub::Name::subname $full_name => $accessor;
        Sub::Install::reinstall_sub({
            into => $class_name,
            as   => $accessor_name,
            code => $accessor,
        });
    }
    elsif (@src) {
        my $src = join("\n",@src);
        #print ">>$src<<\n";
        eval $src;
        if ($@) {
            die "ERROR IN CALCULATED PROPERTY SOURCE: $class_name $accessor_name\n$@\n";
        }
    }
    else {
        die "Error implementing calcuation accessor for $class_name $accessor_name!";
    }
}

sub mk_dimension_delegate_accessors {
    my ($self, $accessor_name, $ref_class_name, $non_id_properties, $other_accessor_name, $is_transient) = @_;

    # Like mk_rw_accessor, but knows that this accessor is a foreign
    # key to a dimension table, and configures additional accessors.
    # Also makes this accessor "smart", to resolve the dimension
    # id only when needed.

    # Make EAV-like accessors for all of the remote properties
    my $class_name = $self->class_name;
    
    my $full_name = join( '::', $class_name, $other_accessor_name );
    my $other_accessor = Sub::Name::subname $full_name => sub {
        my $self = shift;
        my $delegate_id = $self->{$accessor_name};
        if (defined($delegate_id)) {
            # We're currently delegating.
            my $delegate = $ref_class_name->get($delegate_id);
            if (not @_) {
                # A simple get.  Delegate.
                return $delegate->$other_accessor_name(@_);
            }
            else {
                # We're setting a value.
                # Switch from delegating to local access.
                # We'll switch back next-time the dimension ID
                # is actually requested by its accessor
                # (farther below).
                my $old = $delegate->$other_accessor_name;
                my $new = shift;                    
                if (do { no warnings; $old ne $new }) {
                    $self->{$accessor_name} = undef;
                    for my $property (@$non_id_properties) {
                        if ($property eq $other_accessor_name) {
                            # set the value locally
                            $self->{$property} = $new;
                        }
                        else {
                            # grab the data from the (now previous) delegate
                            $self->{$property} = $delegate->$property;
                        }
                    }
                    $self->signal_change( $other_accessor_name, $old, $new ) unless $is_transient;
                    return $new;
                }
            }
        }
        else {
            # We are not currently delegating.
            if (@_) {
                # set
                my $old = $self->{ $other_accessor_name };
                my $new = shift;
                if ($old ne $new)
                {
                    $self->{ $other_accessor_name } = $new;
                    $self->signal_change( $other_accessor_name, $old, $new ) unless $is_transient;
                }
                return $new;
            }
            else {
                # get
                return $self->{ $other_accessor_name };
            }
        }
    };
    
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $other_accessor_name,
        code => $other_accessor,
    });
}

sub mk_dimension_identifying_accessor {
    my ($self, $accessor_name, $ref_class_name, $non_id_properties, $is_transient) = @_;

    # Like mk_rw_accessor, but knows that this accessor is a foreign
    # key to a dimension table, and configures additional accessors.
    # Also makes this accessor "smart", to resolve the dimension
    # id only when needed.

    # Make EAV-like accessors for all of the remote properties
    my $class_name = $self->class_name;

    # Make the actual accessor for the id_by property
    my $full_name = join( '::', $class_name, $accessor_name );
    my $accessor = Sub::Name::subname $full_name => sub {
        if (@_ > 1) {
            my $old = $_[0]->{ $accessor_name };
            my $new = $_[1];
            if ($old ne $new)
            {
                $_[0]->{ $accessor_name } = $new;
                $_[0]->signal_change( $accessor_name, $old, $new ) unless $is_transient;
            }
            return $new;
        }
        if (not defined $_[0]->{ $accessor_name }) {
            # Resolve an ID for the current set of values
            # Switch to delegating to that object.
            my %params;
            my $self = $_[0];
            @params{@$non_id_properties} = delete @$self{@$non_id_properties};
            my $delegate = $ref_class_name->get_or_create(%params);
            return undef unless $delegate;
            $_[0]->{ $accessor_name } = $delegate->id;
        }
        return $_[0]->{ $accessor_name };
    };
    
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $accessor_name,
        code => $accessor,
    });
}

sub mk_class_accessor
{
    no warnings;
    my ($self, $class_name, $accessor_name, $column_name, $variable_name) = @_;
    $variable_name ||= $accessor_name;
    no strict 'refs';
    my $full_accessor_name = $class_name . "::" . $accessor_name;
    my $src = qq(
        sub $full_accessor_name {
            if (\@_ > 1) {
                \$$variable_name = pop;
            }
            return \$$variable_name;
        }
    );
    print "class accessor: $src\n";
    eval $src;
    if ($@) {
        die "Cannot generate class accessor $accessor_name: $@";
    }
    my $accessor;
    unless ($accessor = $class_name->can($accessor_name)) {
        die "Error generating class accessor $accessor_name.  Not found after eval.";
    }

    if ($column_name)
    {
        *{$class_name ."::" . $column_name}  = $accessor;

        # These are for backward-compatability with old modules.  Remove asap.
        ${$class_name . '::column_for_property'}
            {$accessor_name} = $column_name;

        ${$class_name . '::property_for_column'}
            {$column_name} = $accessor_name;
    }
}


sub mk_object_set_accessors {
    my ($self, $class_name, $singular_name, $plural_name, $reverse_id_by, $r_class_name, $where) = @_;

    unless ($plural_name) {
        # TODO: we can handle a reverse_id_by when there is only one item.  We're just not coded-to yet.
        die "Bad property description for $class_name $singular_name: expected is_many with reverse_id_by!";
    }

    # These are set by the resolver closure below, and kept in scope by the other closures
    my $rule_template;
    my $r_class_meta;
    my @property_names;
    my @where = ($where ? @$where : ());
    
    my $rule_resolver = sub {
        my ($obj) = @_;        
        eval {
            eval "use $r_class_name";
            $r_class_name->class;
            $r_class_meta = UR::Object::Type->get(class_name => $r_class_name);
        };
        if ($r_class_meta and not $reverse_id_by) {
            # we have a real class on the other end, and it did not specify how to link back to us
            # try to infer how, otherwise fall back to the same logic we use with "primitives"
            my @possible_relationships = UR::Object::Reference->get(
                class_name => $r_class_name,
                r_class_name => $class_name
            );
            #print "got " . join(", ", map { $_->id } @possible_relationships) . "\n";
            if (@possible_relationships > 1) {
                die "$class_name has an ambiguous definition for property \"$singular_name\"."
                    . "  The target class $r_class_name has " . scalar(@possible_relationships) 
                    . " relationships which reference back to $class_name."
                    . "  Correct by adding \"reverse_id_by => X\" to ${class_name}'s \"$singular_name\" definition one of the following values:  " 
                    . join(",",map { '"' . $_->delegation_name . '"' } @possible_relationships) . ".\n";
            }
            elsif (@possible_relationships == 1) {
                $reverse_id_by = $possible_relationships[0]->delegation_name;
            }
            elsif (@possible_relationships == 0) {
                # we now fall through to the logic below and try direct arrayref storage
                #die "No relationships found between $r_class_name and $class_name.  Error in definition for $class_name $singular_name!"
            }
        }
        if ($reverse_id_by) {
            # join to get the data...
            my $property_meta = $r_class_meta->get_property_meta_by_name($reverse_id_by);
            my @property_links = $property_meta->id_by_property_links;
            #my @property_links = UR::Object::Reference::Property->get(tha_id => $r_class_name . '::' . $reverse_id_by); 
            unless (@property_links) {
                #$DB::single = 1;
                Carp::confess("No property links for $r_class_name -> $reverse_id_by?  Cannot build accessor for $singular_name/$plural_name relationship.");
            }
            my %get_params;            
            for my $link (@property_links) {
                my $my_property_name = $link->r_property_name;
                push @property_names, $my_property_name;
                $get_params{$link->property_name}  = $obj->$my_property_name;
            }
            my $tmp_rule = $r_class_name->get_rule_for_params(%get_params);
            $rule_template = $tmp_rule->get_rule_template;
            unless ($rule_template) {
                die "Error generating rule template to handle indirect relationship $class_name $singular_name referencing $r_class_name!";
            }
        }
        else {
            # data is stored locally on the hashref
            #die "No relationships found between $r_class_name and $class_name.  Error in definition for $class_name $singular_name!"
        }
    };

    my $rule_accessor = Sub::Name::subname $class_name ."::__$singular_name" . '_rule' => sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        unless ($rule_template) {
            die "no indirect rule available for locally-stored 'has-many' relationship";
        }
        if (@_ or @where) {
            my $tmp_rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names); 
            return $r_class_name->get_rule_for_params($tmp_rule->params_list,@where, @_);
        }
        else {
            return $rule_template->get_rule_for_values(map { $self->$_ } @property_names); 
        }
    };
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => "__$singular_name" . '_rule',
        code => $rule_accessor,
    });


    my $list_accessor = Sub::Name::subname $class_name ."::$plural_name" => sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        if ($rule_template) { 
            my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names); 
            if (@_ or @where) {
                return $r_class_name->get($rule->params_list,@where,@_);
            }
            else {
                return $r_class_name->get($rule);
            }
        }
        else {
            if (@_) {
                if (@_ != 1 or ref($_[0]) ne 'ARRAY' ) {
                    die "expected a single arrayref when setting a multi-value $class_name $plural_name!  Got @_";
                }
                $self->{$plural_name} = [ @{$_[0]} ];
                return @{$_[0]};
            }
            else {
                return unless $self->{$plural_name};
                return @{ $self->{$plural_name} };
            }
        }
    };
    
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $plural_name,
        code => $list_accessor,
    });
    
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $singular_name . '_list',
        code => $list_accessor,
    });
    
    my $arrayref_accessor = Sub::Name::subname $class_name ."::$singular_name" . '_arrayref' => sub {
        return [ $list_accessor->(@_) ];
    };
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $singular_name . '_arrayref',
        code => $arrayref_accessor,
    });

    my $iterator_accessor = Sub::Name::subname $class_name ."::$singular_name" . '_iterator' => sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        if ($rule_template) {
            my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names); 
            return UR::Object::Iterator->create_for_filter_rule($rule);
        }
        else {
            die "value iterator not implemented.  its simple!  please do it...";
            return UR::Value::Iterator->create_for_value_arrayref($self->{$plural_name} || []);
        }
    };
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $singular_name . '_iterator',
        code => $iterator_accessor,
    });
    
    # These will behave specially if the rule does not specify the ID, or all of the ID.
    my @params_prefix;
    my $params_prefix_resolved = 0;
    my $params_prefix_resolver = sub {
        # handle the case of has-many primitives
        return unless $r_class_meta;

        my $r_ids = $r_class_meta->get_property_meta_by_name($reverse_id_by)->{id_by};
        my @id_property_names = $r_class_name->get_class_object->id_property_names;
        @params_prefix = 
            grep { 
                my $id_property_name = $_;
                ( (grep { $id_property_name eq $_ } @$r_ids) ? 0 : 1)
            }
            @id_property_names;
        
        # We only do the special single-value spec when there is one property not specified by the rule.
        # This is common for a multi-column primary key where all columns reference a parent object, except an index value, etc.
        @params_prefix = () unless scalar(@params_prefix) == 1;
        $params_prefix_resolved = 1;
    };

    my $single_accessor = Sub::Name::subname $class_name ."::$singular_name" => sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        if ($rule_template) {
            my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names);
            $params_prefix_resolver->() unless $params_prefix_resolved;
            unshift @_, @params_prefix if @_ == 1;
            if (@_) {
                return my $obj = $r_class_name->get($rule->params_list,@_);
            }
            else {
                return my $obj = $r_class_name->get($rule);
            }
        }
        else {
            return unless $self->{$plural_name};
            if (@_ > 1) {
                die "rule-based selection of single-item accessor not supported.  Instead of single value, got @_";
            }
            my @matches = grep { $_ eq $_[0]  } @{ $self->{$plural_name} };
            return $matches[0] if @matches < 2;
            return $self->context_return(@matches); 
        }
    };
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => $singular_name,
        code => $single_accessor,
    });

    my $add_accessor = Sub::Name::subname $class_name ."::add_$singular_name" => sub {
        # TODO: this handles only a single item when making objects: support a list of hashrefs
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        if ($rule_template) {
            $params_prefix_resolver->() unless $params_prefix_resolved;
            unshift @_, @params_prefix if @_ == 1;
            my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names);        
            $r_class_name->create($rule->params_list,@where,@_);
        }
        else {
            if ($r_class_meta) {
                my $new = $r_class_name->create(@where,@_);
                return unless $new;
                push @{ $self->{$plural_name} ||= [] }, $new;
            }
            else { 
                if (@_ != 1) {
                    die "$class_name add_$singular_name expects a single value to add.  Got @_";
                }
                push @{ $self->{$plural_name} ||= [] }, $_[0];
                return $_[0];
            }
        }
    };
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => "add_$singular_name",
        code => $add_accessor,
    });

    my $remove_accessor = Sub::Name::subname $class_name ."::remove_$singular_name" => sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        if ($rule_template) {
            my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names);
            $params_prefix_resolver->() unless $params_prefix_resolved;
            unshift @_, @params_prefix if @_ == 1;        
            my @matches = $r_class_name->get($rule->params_list,@_);
            my $trans = UR::Context::Transaction->begin;
            @matches = map {
                $_->delete or die "Error deleting $r_class_name " . $_->id . " for remove_$singular_name!: " . $_->error_message;
            } @matches;
            $trans->commit;
            return @matches;
        }
        else {
            # direct storage in an arrayref
            $self->{$plural_name} ||= []; 
            if ($r_class_meta) {
                # object
                my @remove;
                my @keep;
                my $rule = $r_class_name->get_rule_for_params(@_);
                for my $value (@{ $self->{$plural_name} }) {
                    if ($rule->evaluate($value)) {
                        push @keep, $value;
                    }
                    else {
                        push @remove, $value;
                    }
                }
                if (@remove) {
                    @{ $self->{$plural_name} } = @keep;
                }
                return @remove;
            }
            else {
                # value (or non-ur object)
                if (@_ == 1) {
                    # remove specific value
                    my $removed;
                    my $n = 0;
                    for my $value (@{ $self->{$plural_name} }) {
                        if ($value eq $_[0]) {
                            $removed = splice(@{ $self->{$plural_name} }, $n, 1);
                            die unless $removed eq $value;
                            return $removed;
                        }
                        $n++;
                    }
                    die "Failed to find item @_ in $class_name $plural_name (@{$self->{$plural_name}})!";
                }
                elsif (@_ == 0) {
                    # remove all if no params are specified
                    @{ $self->{$plural_name} ||= [] } = ();
                }
                else {
                    die "$class_name remove_$singular_name should be called with a specific value.  Params are only usable for ur objects!  Got: @_";
                }
            }
        }
    };
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => "remove_$singular_name",
        code => $remove_accessor,
    });

}

use Data::Dumper;

sub initialize_direct_accessors {
    my $self = shift;
    my $class_name = $self->{class_name};    
    my $type_name = $self->{type_name};

    my %id_property_names;
    for my $property_name (@{ $self->{id_by} }) {
        $id_property_names{$property_name} = 1;
        next if $property_name eq "id";     
    }
    
    my %dimensions_by_fk;
    for my $property_name (sort keys %{ $self->{has} }) {
        my $property_data = $self->{has}{$property_name};
        if ($property_data->{is_dimension}) {
            my $id_by = $property_data->{id_by};
            unless ($id_by) {
                die "No id_by specified for dimension $property_name?";
            }
            if (@$id_by != 1) {
                die "The id_by specified for dimension $property_name must list a single property name!";
            }        
            
            my $dimension_class_name = $property_data->{data_type};
            $dimensions_by_fk{$id_by->[0]} = $dimension_class_name;
             
            my $ref_class_meta = $dimension_class_name->get_class_object;
            my %remote_id_properties = map { $_ => 1 } $ref_class_meta->id_property_names;
            my @non_id_properties = grep { not $remote_id_properties{$_} } $ref_class_meta->all_property_names;        
            for my $expected_delegate_property_name (@non_id_properties) {
                unless ($self->{has}{$expected_delegate_property_name}) {
                    $self->{has}{$expected_delegate_property_name} = {
                        $self->_normalize_property_description(
                            $expected_delegate_property_name,
                            { via => $property_name, to => $expected_delegate_property_name, implied_by => $property_name }
                        )
                    }
                }
            }
        }
    }    

    for my $property_name (sort keys %{ $self->{has} }) {
        my $property_data = $self->{has}{$property_name};
        
        my $accessor_name = $property_name;
        my $column_name = $property_data->{column_name};
        my $attribute_name = $property_data->{attribute_name};
        my $is_transient = $property_data->{is_transient};
        my $where = $property_data->{where};
        
        #my ($props, $cols) = $class_name->_all_properties_columns;
        
        do {
            # Handle the case where the software module has an explicit
            # override for one of the accessors.
            no strict 'refs';
            my $isa = \@{ $class_name . "::ISA" };
            my @old_isa = @$isa;
            @$isa = ();
            if ($class_name->can($property_name)) {
                #warn "property $class_name $property_name exists!";
                $accessor_name = "__$property_name";
            }
            @$isa = @old_isa;
        };
        
        my $accessor_type;
        my @calculation_fields = (qw/calculate calc_perl calc_sql calculate_from/);
        if (my $id_by = $property_data->{id_by}) {
            my $r_class_name = $property_data->{data_type};
            $self->mk_id_based_object_accessor($class_name, $accessor_name, $id_by, $r_class_name,$where);
        }
        elsif (my $via = $property_data->{via}) {
            my $to = $property_data->{to} || $property_data->{property_name};
            if ($property_data->{is_mutable}) {
                my $singular_name;
                if ($property_data->{'is_many'}) {
                    require Lingua::EN::Inflect;
                    $singular_name = Lingua::EN::Inflect::PL_V($accessor_name);
                }
                $self->mk_indirect_rw_accessor($class_name,$accessor_name,$via,$to,$where,$property_data->{'is_many'} && $singular_name);
            }
            else {
                $self->mk_indirect_ro_accessor($class_name,$accessor_name,$via,$to,$where);
            }
        }
        elsif (my $calculate = $property_data->{calculate}) {
            $self->mk_calculation_accessor(
                $class_name,
                $accessor_name,
                $property_data->{calculate},
                $property_data->{calculate_from},
                $property_data->{calculate_params},
                $property_data->{is_constant},
            );
        } 
        elsif (my $calculate_sql = $property_data->{'calculate_sql'}) {
            # The data gets filled in by the object loader behind the scenes.
            # To the user, it's a read-only property
            $self->mk_ro_accessor($class_name, $accessor_name, $calculate_sql);

        }
        elsif ($property_data->{is_many} or $property_data->{reverse_id_by}){
            my $reverse_id_by = $property_data->{reverse_id_by};
            my $r_class_name = $property_data->{data_type};
            my $singular_name;
            my $plural_name;
            if ($property_data->{is_many}) {
                require Lingua::EN::Inflect;
                $plural_name = $accessor_name;
                $singular_name = Lingua::EN::Inflect::PL_V($plural_name);
            }
            else {
                $singular_name = $accessor_name;
            }
            $self->mk_object_set_accessors($class_name, $singular_name, $plural_name, $reverse_id_by, $r_class_name, $where);
        }        
        else {        
            # Just use key/value pairs in the hash for normal
            # table stuff, and also non-database stuff.

            #if ($column_name) {
            #    push @$props, $property_name;
            #    push @$cols, $column_name;
            #}

            if ($id_property_names{$property_name} or not $property_data->{is_mutable}) {
            	$accessor_type = 'ro';
            }
            else {
            	$accessor_type = 'rw';
            }
							
            my $maker = "mk_${accessor_type}_accessor";
            $self->$maker($class_name, $accessor_name, $column_name, $property_name,$is_transient);
        }
    }    
    
    # right now we just stomp on the default accessors constructed above where they are:
    # 1. the fk behind a dimensional relationships
    # 2. the indirect properties created for the dimensional relationship
    for my $dimension_id (keys %dimensions_by_fk) {
        my $dimension_class_name = $dimensions_by_fk{$dimension_id};
        my $ref_class_meta = $dimension_class_name->get_class_object;
        my %remote_id_properties = map { $_ => 1 } $ref_class_meta->id_property_names;
        my @non_id_properties = grep { not $remote_id_properties{$_} } $ref_class_meta->all_property_names;        
        for my $added_property_name (@non_id_properties) {
            $self->mk_dimension_delegate_accessors($dimension_id,$dimension_class_name, \@non_id_properties, $added_property_name);
        }
        $self->mk_dimension_identifying_accessor($dimension_id,$dimension_class_name, \@non_id_properties);
    }
    
    return 1;
}


1;
