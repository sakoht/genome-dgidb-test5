#REVIEW fdu 11/17/2009
#Need documentation

package Genome::Measurable; 

use strict;
use warnings;

use Genome;

require Carp;

class Genome::Measurable {
    table_name => 'GSC.PHENOTYPE_MEASURABLE',
    is_abstract => 1,
    subclassify_by => '_subclass_by_subject_type',
    id_by => [
        subject_id => { 
            is => 'Number',
            doc => 'the numeric ID for the specimen in both the LIMS and the analysis system', 
        },
    ],
    has => [
        subject_type => {
            is => 'Text',
            column_name =>'SUBJECT_TYPE',
        },
        # These are here, and should be overidden in the subclass
        name => { column_name => '', },
        common_name => { default_value => '', column_name => '', },
    ],
    data_source => 'Genome::DataSource::GMSchema',
};

sub _subclass_by_subject_type {
    my ($measurable) = @_;

    #print Data::Dumper::Dumper(\@_);
    my $subject_type = $measurable->subject_type;
    if ( $subject_type eq 'organism sample' or $subject_type eq 'organism_sample' ) {
        return 'Genome::Sample';
    }
    elsif ( $subject_type eq 'organism taxon' or $subject_type eq 'organism_taxon' ) {
        return 'Genome::Taxon';
    }
    elsif ( $subject_type eq 'organism individual' or $subject_type eq 'organism_individual' ) {
        return 'Genome::Individual';
    }
    elsif ( $subject_type eq 'population group' or $subject_type eq 'population_group' ) {
        return 'Genome::Individual';
    }
    else {
        Carp::confess("Unknown subject type ($subject_type), can't determine approporate subclass");
    }
}

1;

