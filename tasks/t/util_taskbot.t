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
use App::Wubot::Util::Taskbot;


has taskbot => (
    is   => 'ro',
    lazy => 1,
    clearer => 'reset_taskbot',
    default => sub {

        my $tempdir     = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
        my $tempbodydir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

        my $taskutil = App::Wubot::Util::Taskbot->new( { dbfile  => "$tempdir/tasks.sql",
                                                         bodydir => $tempbodydir,
                                                     } );
    },
);

test "insert task" => sub {
    my ($self) = @_;

    $self->reset_taskbot; # this test requires a fresh one

    my $task = { title    => "test title",
              };

    ok( my $results = $self->taskbot->create_task( $task ),
        "calling create_task method"
    );

    is( $results->{taskid},
        "TASKBOT-1",
        "Checking that taskid for first task is taskbot-1"
    );

    $task->{taskid} = $results->{taskid};

    is_deeply( $results,
               $task,
               "Checking that inserted task matches original task"
           );

    ok( my ( $got_task ) = $self->taskbot->get_task( $results->{taskid} ),
        "Getting task with get_task method"
    );

    # compare original task and got_task

    # defaults
    $task->{id} = 1;
    $task->{type} = 'taskbot';

    # remove undefined keys from database query for comparison
    for my $key ( keys %{ $got_task } ) {
        if ( ! defined $got_task->{$key} ) {
            delete $got_task->{$key};
        }
    }

    is_deeply( $got_task,
               $task,
               "Checking that retrieved task matches inserted task"
           );

};

test "testing all task fields" => sub {
    my ($self) = @_;

    $self->reset_taskbot; # this test requires a fresh one

    my $now = time;

    my $task = { title      => "test title 2",
                 priority   => 50,
                 status     => 'TODO',
                 deadline   => 12345,
                 scheduled  => 12345,
                 duration   => '1h',
                 recurrence => '1w',
                 color      => 'blue',
                 category   => 'testcase',
                 type       => 'TASKBOT',
             };

    $self->taskbot->create_task( $task, $now );

    # compare original task and got_task
    $task->{id}         = 1;
    $task->{taskid}     = "TASKBOT-1";
    $task->{lastupdate} = $now;

    my ( $got_task ) = $self->taskbot->get_task( $task->{taskid} );

    is_deeply( $got_task,
               $task,
               "Checking that retrieved task matches inserted task"
           );

};

test "change status" => sub {
    my ($self) = @_;

    $self->reset_taskbot; # this test requires a fresh one

    my $task = { title    => "test title",
                 status   => 'TODO',
              };

    $task = $self->taskbot->create_task( $task );

    $task->{status} = 'DONE';

    ok( $self->taskbot->update_task( $task->{taskid}, $task ),
        "calling update_task"
    );

    is( $self->taskbot->get_task( $task->{taskid} )->{status},
        'DONE',
        "Checking that status was updated to 'DONE'"
    );

};

test "mark recurring task done" => sub {
    my ($self) = @_;

    $self->reset_taskbot; # this test requires a fresh one

    my$ now = time;

    my $task = { title      => "test title",
                 status     => 'TODO',
                 recurrence => '1w',
                 deadline   => $now,
                 scheduled  => $now,
              };

    $task = $self->taskbot->create_task( $task );

    $task->{status} = 'DONE';
    ok( $self->taskbot->update_task( $task->{taskid}, $task, $now ),
        "calling update_task"
    );

    is( $self->taskbot->get_task( $task->{taskid} )->{status},
        'TODO',
        "Checking that status was returned to 'TODO' for recurring task"
    );

    is( $self->taskbot->get_task( $task->{taskid} )->{scheduled},
        $now + 7*24*60*60,
        "Checking that schedule moved to 7 days later"
    );
    is( $self->taskbot->get_task( $task->{taskid} )->{deadline},
        $now + 7*24*60*60,
        "Checking that deadline moved to 7 days later"
    );

    $task->{status} = 'DONE';
    ok( $self->taskbot->update_task( $task->{taskid}, $task, $now+1 ),
        "calling update_task"
    );

    is( $self->taskbot->get_task( $task->{taskid} )->{status},
        'TODO',
        "Checking that status was returned to 'TODO' for recurring task"
    );

    is( $self->taskbot->get_task( $task->{taskid} )->{scheduled},
        $now + 7*24*60*60 + 1,
        "Checking that schedule moved to 7 days later"
    );
    is( $self->taskbot->get_task( $task->{taskid} )->{deadline},
        $now + 7*24*60*60 + 1,
        "Checking that deadline moved to 7 days later"
    );
};


run_me;
done_testing;
