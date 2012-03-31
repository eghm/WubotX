#!/perl
use strict;
use warnings;

use Test::More;

for my $lib ( 'Growl::Tiny',
              'App::Wubot::Logger',
              'App::Wubot::Reactor::Growl' ) {

    eval "use $lib";
    plan skip_all => "Failed to load $lib for this test case" if $@;
}

plan 'no_plan';

ok( my $growl = App::Wubot::Reactor::Growl->new(),
    "Creating new growl reactor object"
);

is( $growl->react( { subject => 'foo' } )->{growl}->{results},
    1,
    "Checking that notification sent if message contains a subject"
);

is( $growl->react( { foo => 'bar' } )->{growl},
    undef,
    "Checking that no notification sent if message does not contain a subject"
);

is( $growl->react( { subject => 'foo', quiet => 1 } )->{growl},
    undef,
    "Checking that growl notification skipped when 'quiet' flag set"
);

is( $growl->react( { subject => 'foo', quiet_growl => 1 } )->{growl},
    undef,
    "Checking that growl notification skipped when 'quiet_growl' flag set"
);

#_* priority

is( $growl->react( { subject => 'foo', priority => 10 } )->{growl}->{priority},
    10,
    "Checking that growl_priority set to message priority"
);

is( $growl->react( { subject => 'priority 2', priority => '2' } )->{growl}->{priority},
    2,
    "Checking that growl_priority set to '2'"
);
is( $growl->react( { subject => 'priority 1', priority => '1' } )->{growl}->{priority},
    1,
    "Checking that growl_priority set to '1'"
);
is( $growl->react( { subject => 'priority 0', priority => '0' } )->{growl}->{priority},
    0,
    "Checking that growl_priority set to '0'"
);
is( $growl->react( { subject => 'priority -1', priority => '-1' } )->{growl}->{priority},
    -1,
    "Checking that growl_priority set to '-1'"
);
is( $growl->react( { subject => 'priority -2', priority => '-2' } )->{growl}->{priority},
    -2,
    "Checking that growl_priority set to '-2'"
);

is( $growl->react( { subject => 'non-sticky' } )->{growl}->{sticky},
    0,
    "Checking that 'sticky' not enabled by default"
);

is( $growl->react( { subject => 'sticky', sticky => 1 } )->{growl}->{sticky},
    1,
    "Checking that 'sticky' enabed when message 'sticky' flag set"
);


