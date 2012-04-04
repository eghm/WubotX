#!/perl
use strict;

use File::Temp qw/ tempdir /;
use Test::More 'no_plan';
use Test::Differences;

use App::Wubot::Logger;
use App::Wubot::Plugin::Uptime;

ok( my $check = App::Wubot::Plugin::Uptime->new( { class      => 'App::Wubot::Plugin::Uptime',
                                                   cache_file => "/dev/null",
                                                   key        => 'Uptime-testcase',
                                                   reactor    => sub {},
                                               } ),
    "Creating a new Uptime check instance"
);

{
    if ( -r "/usr/bin/uptime" ) {
        ok( my $results = $check->check( { config => { 'command' => '/usr/bin/uptime' }  } ),
            "Calling check() method"
        );

        ok( $results->{react}->{load01},
            "Checking that load01 parsed from uptime command"
        );

        ok( $results->{react}->{load05},
            "Checking that load05 parsed from uptime command"
        );

        ok( $results->{react}->{load15},
            "Checking that load15 parsed from uptime command"
        );
    }
}


is_deeply( [ $check->_parse_uptime( " 16:52pm  up 35 days  2:29,  18 users,  load average: 0.57, 0.60, 0.66" ) ],
           [ qw( 0.57 0.60 0.66 ) ],
           "Parsing OS X uptime string"
       );


is_deeply( [ $check->_parse_uptime( " 4:53PM  up 26 days, 19:22, 4 users, load averages: 0.23, 0.20, 0.15" ) ],
           [ qw( 0.23 0.20 0.15 ) ],
           "Parsing FreeBSD uptime string"
       );

is_deeply( [ $check->_parse_uptime( " 17:55:52 up 10 days, 19:38,  1 user,  load average: 16.01, 14.77, 14.62" ) ],
           [ qw( 16.01 14.77 14.62 ) ],
           "Parsing bluehost uptime string"
       );

is_deeply( [ $check->_parse_uptime( "16:42  up  5:18, 5 users, load averages: 0.16 0.23 0.24" ) ],
           [ qw( 0.16 0.23 0.24 ) ],
           "Parsing buji uptime string"
       );



