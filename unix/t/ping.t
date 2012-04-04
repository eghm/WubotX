#!/perl
use strict;

use File::Temp qw/ tempdir /;
use Test::More 'no_plan';
use Test::Differences;

use App::Wubot::Logger;
use App::Wubot::Plugin::Ping;

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );


ok( my $check = App::Wubot::Plugin::Ping->new( { class      => 'App::Wubot::Plugin::OsxIdle',
                                                 cache_file => '/dev/null',
                                                 key        => 'OsxIdle-testcase',
                                                 reactor    => sub {},
                                             } ),
    "Creating a new Ping check instance"
);

{
    my $config = { host => 'localhost',
                   num_packets => 2,
               };

    ok( my $results = $check->check( { config => $config } ),
        "Calling check() method"
    );

    is( $results->{react}->{count},
        2,
        "Checking that 2 packets sent"
    );

    is( $results->{react}->{host},
        "localhost",
        "Checking that pings sent to localhost"
    );
}

{
    my $config = { host => 'asdfjklasdfjkl',
                   num_packets => 1,
               };

    ok( my $results = $check->check( { config => $config } ),
        "Calling check() method for non-existent host"
    );

    is( $results->{react}->{count},
        1,
        "Checking that 1 packets sent"
    );

    is( $results->{react}->{loss},
        1,
        "Checking that 1 packets lost"
    );

    like( $results->{react}->{subject},
          qr/Unable to ping host/,
          "Checking for failure message in subject"
    );
}
