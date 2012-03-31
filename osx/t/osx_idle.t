#!/perl
use strict;

use File::Temp qw/ tempdir /;
use Test::More;
use Test::Differences;

unless ( $^O eq "darwin" ) {
    plan skip_all => "This plugin only supported on OS X";
}

use App::Wubot::Logger;
use App::Wubot::Plugin::OsxIdle;

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
my $cache_file = "$tempdir/storage.yaml";


{
    ok( my $check = App::Wubot::Plugin::OsxIdle->new( { class      => 'App::Wubot::Plugin::OsxIdle',
                                                   cache_file => $cache_file,
                                                   key        => 'OsxIdle-testcase',
                                               } ),
        "Creating a new OSX Idle check instance"
    );

    ok( my $results = $check->check( {} ),
        "Calling check() method"
    );

    ok( exists $results->{react}->{idle_min},
        "Checking that check returned idle minutes: $results->{react}->{idle_min}"
    );

    like( $results->{react}->{idle_min},
          qr/^\d+$/,
          "Checking that check returned a number of idle minutes"
      );

    ok( exists $results->{react}->{idle_sec},
        "Checking that check returned idle seconds: $results->{react}->{idle_sec}"
    );

    like( $results->{react}->{idle_sec},
          qr/^\d+$/,
          "Checking that check returned a number of idle seconds"
      );

}

{
    ok( my $idle = App::Wubot::Plugin::OsxIdle->new( { class      => 'App::Wubot::Plugin::OsxIdle',
                                                  cache_file => $cache_file,
                                                  key        => 'OsxIdle-testcase',
                                              } ),
        "Creating a new OSX Idle check instance"
    );

    my $now = time;

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, {} ) )[0]->{idle_min},
        0,
        "Checking that calculate_idle_status calculated idle_min for 0 seconds"
    );

    is( ( $idle->_calculate_idle_stats( $now, 60, {}, {} ) )[0]->{idle_min},
        1,
        "Checking that calculate_idle_status calculated idle_min for 60 seconds"
    );

    is( ( $idle->_calculate_idle_stats( $now, 23, {}, {} ) )[0]->{idle_sec},
        23,
        "Checking that calculate_idle_status included idle_sec"
    );
}


# active duration
{
    ok( my $idle = App::Wubot::Plugin::OsxIdle->new( { class      => 'App::Wubot::Plugin::OsxIdle',
                                                  cache_file => $cache_file,
                                                  key        => 'OsxIdle-testcase',
                                              } ),
        "Creating a new OSX Idle check instance"
    );

    my $now = time;

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, {} ) )[0]->{active_min},
        0,
        "Checking that calculate_idle_status calculated initial active_state_min as 0"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, {} ) )[0]->{idle_state},
        0,
        "Checking that calculate_idle_status set idle_state false with no idle time"
    );

    is( ( $idle->_calculate_idle_stats( $now, 600, {}, {} ) )[0]->{idle_state},
        1,
        "Checking that calculate_idle_status set idle_state after 10 minutes"
    );

    is( ( $idle->_calculate_idle_stats( $now, 600, {}, {} ) )[0]->{lastupdate},
        $now,
        "Checking that calculate_idle_status set lastupdate to current time"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, { lastupdate => $now-601, active_since => $now-601 } ) )[0]->{active_since},
        $now,
        "Checking that calculate_idle_status reset active_since when data is expired"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, { lastupdate => $now-601, active_since => $now-601 } ) )[0]->{cache_expired},
        1,
        "Checking that calculate_idle_status set cache_expired flag when cache is too old"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, { lastupdate => $now-60, cache_expired => 1 } ) )[0]->{cache_expired},
        undef,
        "Checking that calculate_idle_status cleared cache_expired flag when cache is fresh"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, { lastupdate => $now-601, active_since => $now-601 } ) )[0]->{active_since},
        $now,
        "Checking that calculate_idle_status reset active_since when data is expired"
    );

    is( ( $idle->_calculate_idle_stats( $now, 600, {}, { active_since => $now-601 } ) )[0]->{active_since},
        undef,
        "Checking that calculate_idle_status cleared active_since when going idle"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, { active_since => $now-60 } ) )[0]->{active_since},
        $now-60,
        "Checking that calculate_idle_status did not touch active_since when not idle"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, {} ) )[0]->{active_since},
        $now,
        "Checking that calculate_idle_status calculated initial active_since using current time"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, { idle_since => $now-601 } ) )[0]->{idle_since},
        undef,
        "Checking that calculate_idle_status cleared idle_since when going active"
    );

    is( ( $idle->_calculate_idle_stats( $now, 60*3, {}, { active_since => $now-60*5 } ) )[0]->{active_min},
        2,
        "Checking that calculate_idle_status calculated subtracted small idle time from active_min when active"
    );

        is( ( $idle->_calculate_idle_stats( $now, 600, {}, { idle_since => $now-60 } ) )[0]->{idle_since},
        $now-60,
        "Checking that calculate_idle_status did not touch idle_since when still idle"
     );

    is( ( $idle->_calculate_idle_stats( $now, 600, {}, {} ) )[0]->{idle_since},
        $now-600,
        "Checking that calculate_idle_status calculated initial idle_since using start of idle time"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, {} ) )[0]->{idle_min},
        0,
        "Checking that calculate_idle_status calculated 0 minutes of idle time"
    );

    is( ( $idle->_calculate_idle_stats( $now, 600, {}, {} ) )[0]->{idle_min},
        '10',
        "Checking that calculate_idle_status calculated 10 minutes of idle status"
    );

    is( ( $idle->_calculate_idle_stats( $now, 600, {}, { idle_since => $now-1200 } ) )[0]->{idle_min},
        10,
        "Checking that calculate_idle_status calculated idle_min using idle time, not idle_since"
     );
}

# active after idle
{
    ok( my $idle = App::Wubot::Plugin::OsxIdle->new( { class      => 'App::Wubot::Plugin::OsxIdle',
                                                  cache_file => $cache_file,
                                                  key        => 'OsxIdle-testcase',
                                              } ),
        "Creating a new OSX Idle check instance"
    );

    my $now = time;

    my $cache ={ idle_since    => $now-60*15,
                 idle_state    => 1,
                 idle_min      => 15,
             };

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, $cache ) )[0]->{idle_state},
        0,
        "Checking for idle_state flag when going active"
    );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, $cache ) )[0]->{idle_state_change},
        1,
        "Checking for idle_state_change flag when going active"
    );

    like( ( $idle->_calculate_idle_stats( $now, 0, {}, $cache ) )[0]->{subject},
          qr/active after being idle for 15m/,
          "Checking for 'active after being idle' message"
      );

    is( ( $idle->_calculate_idle_stats( $now, 0, {}, $cache ) )[0]->{subject},
        undef,
        "Checking that no duplicate 'iddle after being active' message is sent"
    );
}


# idle after active
{
    ok( my $idle = App::Wubot::Plugin::OsxIdle->new( { class      => 'App::Wubot::Plugin::OsxIdle',
                                                  cache_file => $cache_file,
                                                  key        => 'OsxIdle-testcase',
                                              } ),
        "Creating a new OSX Idle check instance"
    );

    my $now = time;

    my $cache ={ active_since    => $now-60*15,
                 idle_state      => 0,
                 active_min      => 15,
             };

    is( ( $idle->_calculate_idle_stats( $now, 60*15, {}, $cache ) )[0]->{idle_state},
        1,
        "Checking for idle_state flag when going active"
    );

    is( ( $idle->_calculate_idle_stats( $now, 60*15, {}, $cache ) )[0]->{idle_state_change},
        1,
        "Checking for idle_state_change flag when going active"
    );

    like( ( $idle->_calculate_idle_stats( $now, 60*15, {}, $cache ) )[0]->{subject},
          qr/idle after being active for 15m/,
          "Checking for 'idle after being active' message"
      );

    is( ( $idle->_calculate_idle_stats( $now, 60*15, {}, $cache ) )[0]->{subject},
        undef,
        "Checking that no duplicate 'iddle after being active' message is sent"
    );
}

done_testing;
