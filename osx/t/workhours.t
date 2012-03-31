#!/perl
use strict;

use File::Temp qw/ tempdir /;
use Test::More 'no_plan';
use Test::Differences;

use App::Wubot::Logger;
use App::Wubot::Plugin::WorkHours;

ok( my $check = App::Wubot::Plugin::WorkHours->new( { class      => 'App::Wubot::Plugin::WorkHours',
                                                      cache_file => '/dev/null',
                                                      key        => 'WorkHours-testcase',
                                                      reactor    => sub {},
                                                  } ),
    "Creating a new WorkHours check instance"
);

# 24 hours active
{
    my @rows;
    my $now = time;

    for my $minute ( 1 .. 60*24 ) {
        push @rows, { lastupdate => $now - 60*60*24 + $minute*60,
                      idle_min  => 0,
                  };
    }

    my $stats = $check->_calculate_stats( \@rows  );

    is( $stats->{total_hours},
        24,
        "Checking that total hours is 24"
    );

    is( $stats->{active_hours},
        24,
        "Checking that total active hours is 24"
    );

    is( $stats->{idle_hours},
        0,
        "Checking that total idle hours is 0"
    );

}

# 24 hours idle
{
    my @rows;
    my $now = time;

    for my $minute ( 1 .. 60*24 ) {
        push @rows, { lastupdate => $now - 60*60*24 + $minute*60,
                      idle_min  => 10,
                  };
    }

    my $stats = $check->_calculate_stats( \@rows  );

    is( $stats->{total_hours},
        24,
        "Checking that total hours is 24"
    );

    is( $stats->{idle_hours},
        24,
        "Checking that total idle hours is 24"
    );

    is( $stats->{active_hours},
        0,
        "Checking that total active hours is 0"
    );

}

# half idle and half active
{
    my @rows;
    my $now = time;

    my $idle_min = 0;
    for my $minute ( 1 .. 60 ) {
        push @rows, { lastupdate => $now - 60*60 + $minute*60,
                      idle_min  => $idle_min,
                  };

        if ( $idle_min ) {
            $idle_min = 0;
        }
        else {
            $idle_min = 10;
        }
    }

    my $stats = $check->_calculate_stats( \@rows  );

    is( $stats->{total_hours},
        1,
        "Checking that total hours is 1"
    );

    is( $stats->{idle_hours},
        .5,
        "Checking that total idle hours is .5"
    );

    is( $stats->{active_hours},
        .5,
        "Checking that total active hours is .5"
    );

}

# one point every other minute
{
    my @rows;
    my $now = time;

    for my $minute ( 0 .. 30 ) {
        push @rows, { lastupdate => $now - 60*60 + ( $minute * 60 * 2 ),
                      idle_min   => 0,
                  };
    }

    my $stats = $check->_calculate_stats( \@rows  );

    is( $stats->{total_hours},
        1,
        "Checking that total hours is 1"
    );

    is( $stats->{idle_hours},
        0,
        "Checking that total idle hours is 0"
    );

    is( $stats->{active_hours},
        1,
        "Checking that total active hours is 1"
    );

}


# one point every three minutes
{
    my @rows;
    my $now = time;

    for my $minute ( 0 .. 60 ) {
        push @rows, { lastupdate => $now - 60*60 + ( $minute * 60 * 3 ),
                      idle_min   => 0,
                  };
    }

    my $stats = $check->_calculate_stats( \@rows  );

    is( $stats->{total_hours},
        3,
        "Checking that total hours is 3"
    );

    is( $stats->{idle_hours},
        0,
        "Checking that total idle hours is 0"
    );

    is( $stats->{active_hours},
        3,
        "Checking that total active hours is 3"
    );

}

# one point every 10 minutes
{
    my @rows;
    my $now = time;

    for my $minute ( 0 .. 60 ) {
        push @rows, { lastupdate => $now - 60*60 + ( $minute * 60 * 10 ),
                      idle_min   => 0,
                  };
    }

    my $stats = $check->_calculate_stats( \@rows  );

    is( $stats->{total_hours},
        1,
        "Checking that total hours is 1"
    );

    is( $stats->{idle_hours},
        0,
        "Checking that total idle hours is 0"
    );

    is( $stats->{active_hours},
        1,
        "Checking that total active hours is 1"
    );

}


# one point every 1.5 minutes
{
    my @rows;
    my $now = time;

    for my $minute ( 0 .. 40 ) {
        push @rows, { lastupdate => $now - 60*60 + ( $minute * 60 * 1.5 ),
                      idle_min   => 0,
                  };
    }

    my $stats = $check->_calculate_stats( \@rows  );

    is( $stats->{total_hours},
        1,
        "Checking that total hours is 1"
    );

    is( $stats->{idle_hours},
        0,
        "Checking that total idle hours is 0"
    );

    is( $stats->{active_hours},
        1,
        "Checking that total active hours is 1"
    );

}
