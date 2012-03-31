#!/perl
use strict;

use Test::More 'no_plan';

use App::Wubot::Logger;
use App::Wubot::Obj::Contact;

my $contact = { username => 'dude',
                first_name => 'jeffery',
                last_name => 'lebowski',
                nick => 'dude',
                color => 'green',
                phone_home => '555-1234',
                link => 'http://www.google.com?q=dude',
            };

ok( my $item = App::Wubot::Obj::Contact->new( $contact ),
    "Creating a new 'contact' item for 'dude'"
);

ok( $item->update(),
    "Writing contact to database"
);

is( $item->username,
    'dude',
    'checking that contact username is dude'
);

is( $item->color,
    'green',
    'checking that contact color is set to green'
);

ok( $item->color( 'blue' ),
    'Changing color to blue'
);

ok( $item->update(),
    "Writing contact changes to database"
);

is( $item->color,
    'blue',
    'Checking that color was updated'
);
