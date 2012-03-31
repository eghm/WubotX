#!/perl
use strict;
use warnings;

use File::Temp qw/ tempdir /;
use Test::More;
use Test::Routine;
use Test::Routine::Util;
use YAML;

BEGIN {
    if ( $ENV{HARNESS_ACTIVE} ) {
        $ENV{WUBOT_SCHEMAS} = "config/schemas";
    }
}

use App::Wubot::Logger;
use App::Wubot::Util::CommandQueue;

has util => (
    is   => 'ro',
    lazy => 1,
    clearer => 'reset_util',
    default => sub {

        my $tempdir1     = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
        my $tempdir2     = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

        my $util = App::Wubot::Util::CommandQueue->new( { dbfile  => "$tempdir1/command.sql",
                                                          logdir  => $tempdir2,
                                                      } );

        return $util;
    },
);

test "enqueue and dequeue" => sub {
    my ($self) = @_;

    $self->reset_util; # this test requires a fresh one

    ok( $self->util->enqueue( 'sleep 5', 'testqueue' ),
        "enqueue command"
    );

    ok( my $item = $self->util->get_next( 'testqueue' ),
        "Checking that item was dequeued"
    );

    is( $item->{command},
        'sleep 5',
        "Checking command of dequeued item"
    );

    is( $item->{queue},
        'testqueue',
        "Checking queue of dequeued item"
    );
};

test "processed dequeue" => sub {
    my ($self) = @_;

    $self->reset_util; # this test requires a fresh one

    ok( $self->util->enqueue( 'sleep 5', 'testqueue' ),
        "enqueue command"
    );

    ok( $self->util->get_next( 'testqueue' ),
        "Checking that unstarted item was dequeued"
    );

    ok( $self->util->get_next( 'testqueue' ),
        "Checking that unstarted item was dequeued"
    );

};

test "enqueue and get_next with multiple items" => sub {
    my ($self) = @_;

    $self->reset_util; # this test requires a fresh one

    ok( $self->util->enqueue( 'sleep 1', 'testqueue' ),
        "enqueue first command"
    );

    is( $self->util->get_next( 'testqueue' )->{command},
        "sleep 1",
        "Checking that get_next returns first item"
        );

    ok( $self->util->enqueue( 'sleep 2', 'testqueue' ),
        "enqueue second command"
    );

    ok( $self->util->enqueue( 'sleep 3', 'testqueue' ),
        "enqueue third command"
    );

    is( $self->util->get_next( 'testqueue' )->{command},
        "sleep 1",
        "Checking that get_next still returns first item"
        );
};


test "spawn and check results" => sub {
    my ($self) = @_;

    $self->reset_util; # this test requires a fresh one

    my $item = $self->util->enqueue( 'echo foo', 'testqueue' );

    ok( $self->util->spawn( $item->{id} ),
        "Spawning item id: $item->{id}"
    );

    sleep 3;

    ok( my $results = $self->util->get_item( $item->{id} ),
        'Gathering results for testqueue'
    );

    is( $results->{output},
        "foo\n",
        'Checking command output'
    );

    is( $results->{exit_status},
        0,
        'Checking command status'
    );

    is( $results->{exit_signal},
        0,
        'Checking command status'
    );
};

test 'monitor_queue with no tasks' => sub {
    my ($self) = @_;

    $self->reset_util; # this test requires a fresh one

    ok( ! scalar( $self->util->monitor_queue( 'testqueue' ) ),
        "Checking no tasks in queue"
    );
};

test 'monitor_queue with a single task in queue' => sub {
    my ($self) = @_;

    $self->reset_util; # this test requires a fresh one

    my $item = $self->util->enqueue( 'echo foo', 'testqueue' );

    ok( my @started = $self->util->monitor_queue( 'testqueue' ),
        "calling monitor() method"
    );

    is( scalar @started,
        1,
        'Checking that only one item started in queue'
    );

    is( $started[0]->{subject},
        "testqueue: Spawned new command"
    );

    # plenty of time for fork and sql update in child process
    sleep 3;

    ok( my @done = $self->util->monitor_queue( 'testqueue' ),
        "calling monitor() method"
    );

    is( scalar @done,
        1,
        'Checking that one item done in queue'
    );

    is( $done[0]->{subject},
        "testqueue: Command completed successfully"
    );

};


test 'monitor_queue with long running task' => sub {
    my ($self) = @_;

    $self->reset_util; # this test requires a fresh one

    my $item = $self->util->enqueue( 'sleep 5', 'testqueue' );
    my $item = $self->util->enqueue( 'sleep 3', 'testqueue' );

    # starting monitor to add first task to queue
    $self->util->monitor_queue( 'testqueue' );

    ok( ! $self->util->monitor_queue( 'testqueue' ),
        "calling monitor() method, still running first task"
    );

    ok( ! $self->util->monitor_queue( 'testqueue' ),
        "calling monitor() method, still running first task"
    );


};



run_me;
done_testing;
