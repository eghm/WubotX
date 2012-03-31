#!/perl
use strict;

use File::Temp qw/ tempdir /;
use Test::More;

for my $lib ( 'Astro::MoonPhase',
              'App::Wubot::Logger',
              'App::Wubot::Plugin::MoonPhase' ) {

    eval "use $lib";
    plan skip_all => "Failed to load $lib for this test case" if $@;
}

plan 'no_plan';

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );


ok( my $check = App::Wubot::Plugin::MoonPhase->new( { class      => 'App::Wubot::Plugin::OsxIdle',
                                                 cache_file => '/dev/null',
                                                 key        => 'OsxIdle-testcase',
                                             } ),
    "Creating a new MoonPhase check instance"
);

ok( my $results = $check->check( ),
    "Calling check() method"
);

ok( $results->{react}->{age},
    "Checking that moon age is set"
);

ok( $results->{react}->{phase} && $results->{react}->{phase} > 0 && $results->{react}->{phase} < 1,
    "Checking 'phase' is set to a valid value"
);

