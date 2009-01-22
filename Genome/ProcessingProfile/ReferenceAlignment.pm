package Genome::ProcessingProfile::ReferenceAlignment;

use strict;
use warnings;

use Genome;

my %PROPERTIES = &properties_hash;

class Genome::ProcessingProfile::ReferenceAlignment {
    is => 'Genome::ProcessingProfile',
    sub_classification_method_name => '_resolve_subclass_name',
    has => [
            map {
                $_ => {
                       via => 'params',
                       to => 'value',
                       where => [ name => $_ ],
                       is_optional => (
                                       ( exists $PROPERTIES{$_}->{is_optional} )
                                       ? $PROPERTIES{$_}->{is_optional}
                                       : 0
                                   ),
                       is_mutable => 1,
                       doc => (
                               ( exists $PROPERTIES{$_}->{valid_valiues} )
                               ? sprintf('%s Valid values: %s.', $PROPERTIES{$_}->{doc}, join(', ', @{$PROPERTIES{$_}->{valid_values}}))
                               : $PROPERTIES{$_}->{doc}
                           ),
                   },
               } keys %PROPERTIES
        ],
};

sub properties_hash {
    my %properties = (
                  sequencing_platform => {
                                          doc => 'The sequencing platform from whence the model data was generated',
                                          valid_values => ['454', 'solexa', '3730'],
                                      },
                  dna_type => {
                               doc => 'the type of dna used in the reads for this model',
                               valid_values => ['genomic dna', 'cdna']
                           },
                  genotyper_name => {
                                     doc => 'name of the genotyper for this model',
                                     is_optional => 1,
                                 },
                  genotyper_params => {
                                       doc => 'command line args used for the genotyper',
                                       is_optional => 1,
                                   },
                  indel_finder_name => {
                                        doc => 'name of the indel finder for this model',
                                        is_optional => 1,
                                    },
                  indel_finder_params => {
                                          doc => 'command line args for the indel finder',
                                          is_optional => 1,
                                      },
                  multi_read_fragment_strategy => {
                                                   doc => '',
                                                   is_optional => 1,
                                               },
                  read_aligner_name => {
                                        doc => 'alignment algorithm/software used for this model',
                                    },
                  read_aligner_params => {
                                          doc => 'command line args for the aligner',
                                          is_optional => 1,
                                      },
                  read_calibrator_name => {
                                           doc => '',
                                           is_optional => 1,
                                       },
                  read_calibrator_params => {
                                             doc => '',
                                             is_optional => 1,
                                         },
                  prior_ref_seq => {
                                    doc => '',
                                    is_optional => 1,
                                },
                  reference_sequence_name => {
                                              doc => 'identifies the reference sequence used in the model(required if no prior_ref_seq)',
                                              is_optional => 1,
                                          },
                  align_dist_threshold => {
                                           doc => '',
                                           is_optional => 1,
                                       },
                  );
    return %properties;
}

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    my $class_object = $self->get_class_object;
    for my $property_name ( keys %PROPERTIES ) {
        next if $class_object->{has}->{$property_name}->{is_optional} && !defined($self->$property_name);
        next unless exists $PROPERTIES{$property_name}->{valid_values};
        unless ( grep { $self->$property_name eq $_ } @{$PROPERTIES{$property_name}->{valid_values}} ) {
            $self->error_message(
                                 sprintf(
                                         'Invalid value (%s) for %s.  Valid values: %s',
                                         $self->$property_name,
                                         $property_name,
                                         join(', ', @{$PROPERTIES{$property_name}->{valid_values}}),
                                     )
                             );
            $self->delete;
            return;
        }
    }
    return $self;
}

sub prior {
    my $self = shift;
    warn("For now prior has been replaced with the actual column name prior_ref_seq");
    if (@_) {
        die("Method prior() is read-only since it's deprecated");
    }
    return $self->prior_ref_seq();
}

sub params_for_class {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %properties = &properties_hash;
    return keys %properties;
}

sub filter_ruleset_name {
    #TODO: move into the db so it's not constant
    'basic'
}

sub filter_ruleset_params {
    ''
}


#< SUBCLASSING >#
#
# This is called by the infrastructure to appropriately classify abstract processing profiles
# according to their type name because of the "sub_classification_method_name" setting
# in the class definiton...
sub _resolve_subclass_name {
    my $class = shift;

    my $sequencing_platform;
    if ( ref($_[0]) and $_[0]->can('params') ) {
        my @params = $_[0]->params;
        my @seq_plat_param = grep { $_->name eq 'sequencing_platform' } @params;
        if (scalar(@seq_plat_param) == 1) {
            $sequencing_platform = $seq_plat_param[0]->value;
        }
    }  else {
        my %params = @_;
        $sequencing_platform = $params{sequencing_platform};
    }

    unless ( $sequencing_platform ) {
        my $rule = $class->get_rule_for_params(@_);
        $sequencing_platform = $rule->specified_value_for_property_name('sequencing_platform');
    }

    return ( defined $sequencing_platform ) 
    ? $class->_resolve_subclass_name_for_sequencing_platform($sequencing_platform)
    : undef;
}

sub _resolve_subclass_name_for_sequencing_platform {
    my ($class,$sequencing_platform) = @_;
    my @type_parts = split(' ',$sequencing_platform);
	
    my @sub_parts = map { ucfirst } @type_parts;
    my $subclass = join('',@sub_parts);
	
    my $class_name = join('::', 'Genome::ProcessingProfile::ReferenceAlignment' , $subclass);
    return $class_name;
}

sub _resolve_sequencing_platform_for_class {
    my $class = shift;

    my ($subclass) = $class =~ /^Genome::ProcessingProfile::ReferenceAlignment::([\w\d]+)$/;
    return unless $subclass;

    return lc join(" ", ($subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx));
    
    my @words = $subclass =~ /[a-z\d]+|[A-Z\d](?:[A-Z\d]+|[a-z]*)(?=$|[A-Z\d])/gx;
    return lc(join(" ", @words));
}

1;
