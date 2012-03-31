#!/perl
use strict;

use File::Temp qw/ tempdir /;
use Test::More;

for my $lib ( 'Astro::Sunrise',
              'App::Wubot::Logger',
              'App::Wubot::Plugin::SunRise' ) {

    eval "use $lib";
    plan skip_all => "Failed to load $lib for this test case" if $@;
}

plan 'no_plan';

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

ok( my $check = App::Wubot::Plugin::SunRise->new( { class      => 'App::Wubot::Plugin::OsxIdle',
                                                    cache_file => '/dev/null',
                                                    key        => 'OsxIdle-testcase',
                                                } ),
    "Creating a new SunRise check instance"
);

my $config = { longitude => -122.6362492,
               latitude  => 47.5403732,
           };

my $cache = {};

{
    ok( my $results = $check->check( { config => $config } ),
        "Calling check() method"
    );

    $cache = $results->{cache};

    {
        local $TODO = "debug this failure where time reported may be in the past";
        ok( $results->{react}->{next_utime} > time,
            "Checking that next utime is in the future"
        );
    }

    ok( $results->{react}->{next_until},
        "Checking that next_until is not false"
    );

    ok( ! $results->{react}->{cache_remaining},
        "Cache not used on first check"
    );

}


# {
#     ok( my $results = $check->check( { config => $config, cache => $cache } ),
#         "Calling check() method"
#     );

#     ok( $results->{react}->{next_utime} > time,
#         "Checking that next utime is in the future"
#     );

#     ok( $results->{react}->{next_until} > 0,
#         "Checking that next_until is positive"
#     );

#     ok( $results->{react}->{cache_remaining},
#         "Cache used on second check"
#     );

# }

