package Genome::Model::Command::List::VariantReviewDetails;
use strict;
use warnings;

use above 'Genome';

UR::Object::Type->define(
    class_name => __PACKAGE__, 
    is => 'UR::Object::Command::List',
    has => [
        subject_class_name  => { is_constant => 1, value => 'Genome::VariantReviewDetail' },
        model               => { is_optional => 1 },
        show                => { default_value => 'chromosome,begin_position,end_position,variant_type,somatic_status' },
    ],
);

1;
