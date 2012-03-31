#!/perl
use strict;
use warnings;

use Test::More;

use File::Temp qw/ tempdir /;

use App::Wubot::LocalMessageStore;
use App::Wubot::Reactor::State;
use App::Wubot::Logger;


{
    my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

    ok( my $state = App::Wubot::Reactor::State->new( { cachedir => $tempdir } ),
        "Creating new State reactor object"
    );

    is_deeply( $state->react( { key => 'TestCase', a => 5 }, { field => 'a' } ),
               { key           => 'TestCase',
                 a             => 5,
                 state_init    => 1,
             },
               "Checking that no state change detected on startup, and state_init flag set"
           );
}

my $cases = [
    { desc   => "checking with no state change, 2 times",
      config => { field => 'a', change => 1 },
      cases  => [ { key => 'TestCase', a => 5 }, { key => 'TestCase', a => 5 } ],
      expect => { key           => 'TestCase',
                  a             => 5,
              },
  },
    { desc   => "checking with no state change, 3 times",
      config => { field => 'a', change => 1 },
      cases  => [ { key => 'TestCase', a => 5 }, { key => 'TestCase', a => 5 }, { key => 'TestCase', a => 5 } ],
      expect => { key           => 'TestCase',
                  a             => 5,
              },
  },
    { desc   => "checking state for change on decrease",
      config => { field => 'a', change => 1 },
      cases  => [ { key => 'TestCase', a => 8 }, { key => 'TestCase', a => 3 } ],
      expect => { key           => 'TestCase',
                  a             => 3,
                  subject       => 'TestCase: a changed: 8 => 3',
                  state_change  => -5,
                  state_changed => 1,
              },
  },
    { desc   => "checking state for change on increase",
      config => { field => 'a', change => 1 },
      cases  => [ { key => 'TestCase', a => 3 }, { key => 'TestCase', a => 8 } ],
      expect => { key           => 'TestCase',
                  a             => 8,
                  subject       => 'TestCase: a changed: 3 => 8',
                  state_change  => 5,
                  state_changed => 1,
              },
  },
    { desc   => "checking insignificant state change, within threshold 5",
      config => { field => 'a', change => 5 },
      cases  => [ { key => 'TestCase', a => 5 }, { key => 'TestCase', a => 3 } ],
      expect => { key           => 'TestCase',
                  a             => 3,
                  state_change  => -2,
              },
  },
    { desc   => "checking insignificant state change, within threshold 5",
      config => { field => 'a', change => 5 },
      cases  => [ { key => 'TestCase', a => 5 }, { key => 'TestCase', a => 7 } ],
      expect => { key           => 'TestCase',
                  a             => 7,
                  state_change  => 2,
              },
  },
    { desc   => "checking state for decrease",
      config => { field => 'a', decrease => 1 },
      cases  => [ { key => 'TestCase', a => 8 }, { key => 'TestCase', a => 3 } ],
      expect => { key           => 'TestCase',
                  a             => 3,
                  subject       => 'TestCase: a decreased: 8 => 3',
                  state_change  => -5,
                  state_changed => 1,
              },
  },
    { desc   => "checking state for decrease when value increased",
      config => { field => 'a', decrease => 1 },
      cases  => [ { key => 'TestCase', a => 3 }, { key => 'TestCase', a => 8 } ],
      expect => { key           => 'TestCase',
                  a             => 8,
                  state_change  => 5,
              },
  },

    { desc   => "checking state for increase",
      config => { field => 'a', increase => 1 },
      cases  => [ { key => 'TestCase', a => 3 }, { key => 'TestCase', a => 8 } ],
      expect => { key           => 'TestCase',
                  a             => 8,
                  subject       => 'TestCase: a increased: 3 => 8',
                  state_change  => 5,
                  state_changed => 1,
              },
  },
    { desc   => "checking state for increase when value decreased",
      config => { field => 'a', increase => 1 },
      cases  => [ { key => 'TestCase', a => 8 }, { key => 'TestCase', a => 3 } ],
      expect => { key           => 'TestCase',
                  a             => 3,
                  state_change  => -5,
              },
  },

    { desc   => "increase threshold set to 10, but only increased by 2",
      config => { field => 'a', increase => 10 },
      cases  => [ { key => 'TestCase', a => 3 }, { key => 'TestCase', a => 5 } ],
      expect => { key           => 'TestCase',
                  a             => 5,
                  state_change  => 2,
              },
  },
    { desc   => "decrease threshold set to 10, but only decreased by 2",
      config => { field => 'a', decrease => 10 },
      cases  => [ { key => 'TestCase', a => 5 }, { key => 'TestCase', a => 3 } ],
      expect => { key           => 'TestCase',
                  a             => 3,
                  state_change  => -2,
              },
  },
];


for my $testcase ( @{ $cases } ) {

    my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

    my $state = App::Wubot::Reactor::State->new( { cachedir => $tempdir } );

    for my $idx ( 0 .. $#{ $testcase->{cases} } - 1 ) {
        $state->react( $testcase->{cases}->[$idx], $testcase->{config} );
    }

    my $got = $state->react( $testcase->{cases}->[-1], $testcase->{config} );

    if ( $got->{subject} ) {
        $got->{subject} =~ s|\s\([\d\w]+\)$||;
    }

    is_deeply( $got,
               $testcase->{expect},
               $testcase->{desc}
           );

}

{
    my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

    my $state = App::Wubot::Reactor::State->new( { cachedir => $tempdir } );

    is_deeply( [ $state->monitor() ],
               [ ],
               "Checking that monitor() returns no errors with no data in cache"
           );

    $state->react( { key => 'testkey', testfield => 5, lastupdate => time-50 },
                   { field => 'testfield', change => 10 }
               );

    is_deeply( [ $state->monitor() ],
               [ ],
               "Checking that monitor() returns no errors with cache data updated recently"
           );

    $state->react( { key => 'testkey', testfield => 5, lastupdate => time-2*24*60*60 },
                   { field => 'testfield', change => 10, notify_interval => '1d' } );

    my @results = $state->monitor();

    for my $results ( @results ) {
        ok( $results->{lastupdate},
            "Checking that lastupdate field set in reaction message"
        );
        delete $results->{lastupdate};
    }

    is_deeply( \@results,
               [ { subject => "cache data for testkey:testfield not updated in 2d",
                   key     => 'testkey',
                   mailbox => undef,
                   status  => 'CRITICAL',
               } ],
               "Checking that monitor() returns warning with lastupdate time > 5 minues"
           );
}

{
    my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

    my $state = App::Wubot::Reactor::State->new( { cachedir => $tempdir } );

    $state->react( { key => 'TestCase1', x => 5, lastupdate => time-60*60 },
                   { field => 'a', change => 10, notify_interval => '5m' }
               );

    $state->react( { key => 'TestCase2', x => 5, lastupdate => time-60*60 },
                   { field => 'a', change => 10, notify_interval => '5m' }
               );

    $state->react( { key => 'TestCase3', x => 5, lastupdate => time-60*60 },
                   { field => 'a', change => 10, notify_interval => '5m' }
               );

    my @results = $state->monitor();

    for my $results ( @results ) {
        ok( $results->{lastupdate},
            "Checking that lastupdate field set in reaction message"
        );
        delete $results->{lastupdate};
    }

    is_deeply( \@results,
               [ { key     => 'TestCase1',
                   subject => 'cache data for TestCase1:a not updated in 1h',
                   mailbox => undef,
                   status  => 'CRITICAL',
               },
                 { key     => 'TestCase2',
                   subject => 'cache data for TestCase2:a not updated in 1h',
                   mailbox => undef,
                   status  => 'CRITICAL',
               },
                 { key     => 'TestCase3',
                   subject => 'cache data for TestCase3:a not updated in 1h',
                   mailbox => undef,
                   status  => 'CRITICAL',
               },
             ],
               "Checking that monitor() returns no changes in cache"
           );


}

{
    my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

    {
        my $state = App::Wubot::Reactor::State->new( { cachedir => $tempdir } );

        $state->react( { key => 'TestCase1', x => 5, lastupdate => time-60*60 },
                       { field => 'a', change => 10, notify_interval => '45m' }
                   );

    }
    {
        my $state = App::Wubot::Reactor::State->new( { cachedir => $tempdir } );

        my @results = $state->monitor();

        for my $results ( @results ) {
            ok( $results->{lastupdate},
                "Checking that lastupdate field set in reaction message"
            );
            delete $results->{lastupdate};
        }

        is_deeply( \@results,
                   [ { key     => 'TestCase1',
                       subject => 'cache data for TestCase1:a not updated in 1h',
                       mailbox => undef,
                       status  => 'CRITICAL',
                   },
                 ],
                   "Checking that monitor() finds cache data from previous App::Wubot::Reactor::State instance"
               );

    }
}


{
    my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

    my $state = App::Wubot::Reactor::State->new( { cachedir => $tempdir } );

    $state->react( { key => 'TestCase1', x => 5, lastupdate => time-60*60 },
                   { field => 'a', change => 10, notify_interval => '5s' },
               );

    {
        my @results = $state->monitor();

        for my $results ( @results ) {
            ok( $results->{lastupdate},
                "Checking that lastupdate field set in reaction message"
            );
            delete $results->{lastupdate};
        }

        is_deeply( \@results,
                   [ { key     => 'TestCase1',
                       subject => 'cache data for TestCase1:a not updated in 1h',
                       mailbox => undef,
                       status  => 'CRITICAL',
                   },
                 ],
                   "Checking that monitor() sends a notification for stale cache"
               );
    }

    is_deeply( [ $state->monitor() ],
               [ ],
               "Checking that monitor() does not notify again before end of notify interval"
           );

    sleep 5;

    {
        my @results = $state->monitor();

        for my $results ( @results ) {
            ok( $results->{lastupdate},
                "Checking that lastupdate field set in reaction message"
            );
            delete $results->{lastupdate};
        }

        is_deeply( \@results,
                   [ { key     => 'TestCase1',
                       subject => 'cache data for TestCase1:a not updated in 1h',
                       mailbox => undef,
                       status  => 'CRITICAL',
                   },
                 ],
                   "Checking that monitor() returns notification after notify interval"
               );
    }
}

done_testing;
