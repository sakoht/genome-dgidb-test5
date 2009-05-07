package Vending::Command::Dime;

class Vending::Command::Dime {
    is => 'Vending::Command::InsertMoney',
    has => [
        name => { is_constant => 1, value => 'dime' },
    ],
    doc => 'Insert a dime into the machine',
};

1;

