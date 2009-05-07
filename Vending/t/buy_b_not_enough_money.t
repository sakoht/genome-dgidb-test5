use strict;
use warnings;

use Test::More tests => 12;

use Vending;

my $machine = Vending::Machine->get();
ok($machine, 'Got the Vending::Machine instance');
$machine->_initialize_for_tests();

# Stock the machine so there's something to get
my $prod = Vending::Product->create(name => 'Candy', manufacturer => 'Acme', cost_cents => 100);
ok($prod, 'Defined Candy product');

my $slot_b = Vending::VendSlot->get(name => 'b');
ok($slot_b->add_item(type_name => 'Vending::Inventory', product_id => $prod),'Added Candy to slot a');


ok($machine->insert('quarter'), 'Inserted a quarter');
ok($machine->insert('quarter'), 'Inserted a quarter');
ok($machine->insert('quarter'), 'Inserted a quarter');
ok($machine->insert('nickel'), 'Inserted a nickel');

my @errors;
$machine->message_callback('error', sub { push @errors, $_[0]->text });
my @items = $machine->buy('b');

is(scalar(@items), 0, 'Got back no items');
like($errors[0], qr/You did not enter enough money/, 'Error message indicates we did not enter enough money');

@items = $machine->coin_return();
is(scalar(@items), 4, 'Coin return got back 4 items');

my %item_counts;
foreach my $item ( @items ) {
    $item_counts{$item->name}++;
}

is($item_counts{'quarter'}, 3, 'Three of them were quarters');
is($item_counts{'nickel'}, 1, 'One of them was a nickel');




