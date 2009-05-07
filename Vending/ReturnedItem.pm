package Vending::ReturnedItem;

use strict;
use warnings;
use Vending;

class Vending::ReturnedItem {
    has => [
        name        => { is => 'String' },
        value       => { is => 'Float' },
        source_slot => { is => 'Vending::VendSlot', id_by => 'source_slot_id' },
        price       => { via => 'source_slot', to => 'price' },
        cost_cents  => { via => 'source_slot', to => 'cost_cents' },
    ],
    doc => 'Represents a thing being returned to the user, not stored in the database',
};

# Create Vending::ReturnedItem objects from a product or coin
# To enforce vending machine rules, the passed-in item is deleted
sub create_from_vend_items {
    my($class,@items) = @_;

    my $transaction = UR::Context::Transaction->begin();

    my @returned_items = eval {

        my @returned_items;
        foreach my $item ( @items ) {
            my %create_params = ( name => $item->name, source_slot_id => $item->slot_id );
 
            if ($item->isa('Vending::Coin')) {
                $create_params{'value'} = $item->value_cents;
            } elsif ($item->isa('Vending::Inventory')) {
                $create_params{'value'} = $item->cost_cents;
            } else {
                die "Can't create a Vending::ReturnedItem from an object of type ".$item->class;
            }

            $item->delete();

            my $returned_item = $class->create(%create_params);
            push @returned_items, $returned_item;
        }
        return @returned_items;
    };

    if ($@) {
        $class->error_message($@);
        $transaction->rollback();
    } else {
        $transaction->commit();
        return @returned_items;
    }
}

1;
