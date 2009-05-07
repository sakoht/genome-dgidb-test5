package Vending::ContentType;

use strict;
use warnings;

use Vending;
class Vending::ContentType {
    table_name => 'content_type',
    id_by => [
        type_id => { is => 'integer' },
    ],
    has => [
        name => { is => 'varchar' },

        machine_id => { value => 'Vending::Machine', is_constant => 1, is_class_wide => 1, column_name => '' },
        machine    => { is => 'Vending::Machine', id_by => 'machine_id' },

        count       => { calculate_from => ['type_id'],
                         calculate => \&count_items_by_type,
                         doc => 'How many items of this type are there' },

    ],
    id_sequence_generator_name => 'URMETA_content_type_TYPE_ID_seq',
    doc => 'abstract base class for things the machine knows about',
    schema_name => 'Machine',
    data_source => 'Vending::DataSource::Machine',
};

&_initialize();

sub count_items_by_type {
    my $type_id = shift;

    my $item = Vending::CoinType->get($type_id) || Vending::Product->get($type_id);

    my @objects;
    if ($item->isa('Vending::CoinType')) {
        @objects = Vending::Coin->get(type_id => $type_id);
    }  else {
        @objects = Vending::Inventory->get(product_id => $type_id);
    }
    return scalar(@objects);
}


sub _initialize {
    my $class = shift;

    my $a = Vending::ContentType->get(name => 'dollar');
    unless ($a) {
        __PACKAGE__->status_message("Initializing Vending::ContentType");
        foreach my $name ( qw( dollar quarter dime nickel ) ) {
            Vending::ContentType->create(name => $name);
        }
    }
}
1;
