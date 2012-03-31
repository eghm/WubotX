#!/perl
use strict;
use warnings;

use File::Temp qw/ tempdir /;
use Test::More;
use Test::Routine;
use Test::Routine::Util;
use Test::Differences;

BEGIN {
    if ( $ENV{HARNESS_ACTIVE} ) {
        $ENV{WUBOT_SCHEMAS} = "config/schemas";
    }
}

use App::Wubot::Logger;
use App::Wubot::Reactor::Command;

has reactor => (
    is   => 'ro',
    lazy => 1,
    clearer => 'reset_reactor',
    default => sub {
        my ( $self ) = @_;

        my $tempdir  = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
        $tempdir .= "/tmp";

        my $queuedir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
        $queuedir .= "/queue";

        my $queuedb = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
        $queuedb .= "/commands.sql";

        return App::Wubot::Reactor::Command->new( { logdir => $tempdir, queuedb => $queuedb } );
    },
);

test "run command and capture output" => sub {
    my ($self) = @_;

    $self->reset_reactor;

    my $pwd = `pwd`;
    chomp $pwd;

    is_deeply( $self->reactor->react( { abc => 'xyz' }, { command => 'pwd' } ),
               { command_output => $pwd, command_signal => 0, command_status => 0, abc => 'xyz' },
               "Checking react() run with a configured command"
           );

    is( $self->reactor->react( { test => 'pwd' }, { command_field => 'test' } )->{command_output},
        $pwd,
        "Checking react() run with a command from a field"
    );

    is( $self->reactor->react( { test => 'pwd' },
                         { command_field => 'test', output_field => 'test_output' }
                     )->{test_output},
        $pwd,
        "Checking react() with specified output field"
    );
};

test "run command that fails" => sub {
    my ($self) = @_;

    $self->reset_reactor;

    is_deeply( $self->reactor->react( { abc => 'xyz' }, { command => 'false' } ),
               { command_output => '', command_signal => 0, command_status => 1, abc => 'xyz' },
               "Checking react() run with a command that fails"
           );
};

test "run forked command" => sub {
    my ($self) = @_;

    $self->reset_reactor;

    my $id = 'forker';

    my $queue_results_h = $self->reactor->react(
        { foo     => 'abc' },
        { command => 'sleep 4 && echo finished', fork => $id }
    );

    is( $queue_results_h->{foo},
        'abc',
        "Checking react() returned original message after forking"
    );

    is( $queue_results_h->{command_queued},
        $id,
        "Checking that command was queued"
    );

    ok( ! $self->reactor->monitor(),
        "Calling monitor method to start task, no message sent"
    );

    sleep 3;

    ok( ! $self->reactor->monitor(),
        "Calling monitor method while task is still running, no message sent"
    );

    my $lockfile    = join( "/", $self->reactor->logdir, "$id.pid" );
    my $logfile     = join( "/", $self->reactor->logdir, "$id.log" );
    my $resultsfile = join( "/", $self->reactor->logdir, "$id.yaml" );

    ok( -r $lockfile,
        "Checking that pidfile was created"
    );

    ok( -r $logfile,
        "Checking that log file was created"
    );

    sleep 3;

    ok( ! -r $lockfile,
        "Checking that pidfile was removed when process exited"
    );

    # ok( -r $resultsfile,
    #     "Checking that results file was created"
    # );

    my $results_a = $self->reactor->monitor();

    is( scalar @{ $results_a },
        1,
        "Calling monitor method got 1 result"
    );

    my ( $results_h ) = @{ $results_a };

    ok( $results_h->{lastupdate},
        "Checking that lastupdate time is set"
    );

    delete $results_h->{lastupdate};

    is_deeply( \$results_h,
               \{ command_output => 'finished',
               command_signal    => 0,
               command_queue     => 'forker',
               command_status    => 0,
               foo               => 'abc',
               subject           => "Command succeeded: $id",
               status            => 'OK',
           },
                     "Checking background command results"
                 );

    ok( ! -r $logfile,
        "Checking that logfile was removed"
    );

    ok( ! -r $resultsfile,
        "Checking that results file was removed"
    );

};


test "run forked commands in multiple queues" => sub {
    my ($self) = @_;

    $self->reset_reactor;

    my $id = 'separate';

    my $results1_h = $self->reactor->react( { foo => 'abc' }, { command => 'sleep 1 && echo finished1', fork => "$id.1" } );
    my $results2_h = $self->reactor->react( { foo => 'def' }, { command => 'sleep 1 && echo finished2', fork => "$id.2" } );

    ok( $results1_h->{command_queued},
        "Checking react() for first process was not queued"
    );

    ok( $results2_h->{command_queued},
        "Checking react() for second process was queued"
    );

    ok( ! $self->reactor->monitor(),
        "calling monitor() method to start first command in queue"
    );

    sleep 3;

    my $results3_h = $self->reactor->monitor();

    ok( $results3_h->[0]->{lastupdate},
        "Checking that lastupdate field is set in first message"
    );
    ok( $results3_h->[1]->{lastupdate},
        "Checking that lastupdate field is set in second message"
    );

    delete $results3_h->[0]->{lastupdate};
    delete $results3_h->[1]->{lastupdate};

    is_deeply( \$results3_h,
                \[
                   { command_output => 'finished1',
                     command_queue  => 'separate.1',
                     command_signal => 0,
                     command_status => 0,
                     foo            => 'abc',
                     subject        => "Command succeeded: $id.1",
                     status         => 'OK',
                 },
                   { command_output => 'finished2',
                     command_queue  => 'separate.2',
                     command_signal => 0,
                     command_status => 0,
                     foo            => 'def',
                     subject        => "Command succeeded: $id.2",
                     status         => 'OK',
                 },
               ],
               "Checking background command results"
           );
};

test "command array templating" => sub {
    my ($self) = @_;

    $self->reset_reactor;

    my $config = { command_array => [ 'echo', '{$abc}' ], fork => 'commandarray' };

    $self->reactor->react( { abc => 'xyz' }, $config );

    ok( ! $self->reactor->monitor(),
        "calling monitor() method to start first command in queue"
    );

    sleep 1;

    is_deeply( $self->reactor->monitor()->[0]->{command_output},
               "xyz",
               "Checking react() run with a configured_array command"
           );

    $self->reactor->react( { abc => 'def' }, $config );

    ok( ! $self->reactor->monitor(),
        "calling monitor() method to start first command in queue"
    );

    sleep 1;

    is_deeply( $self->reactor->monitor()->[0]->{command_output},
               "def",
               "Checking react() run with a configured_array command"
           );


};

test "queue defined in fork_field" => sub {
    my ($self) = @_;

    $self->reset_reactor;

    my $id = 'forker';

    my $queue_results_h = $self->reactor->react(
        { foo     => 'abc' },
        { command => 'sleep 4 && echo finished', fork => 1, fork_field => 'foo' }
    );

    is( $queue_results_h->{foo},
        'abc',
        "Checking react() returned original message after forking"
    );

    is( $queue_results_h->{command_queued},
        'abc',
        "Checking that command was queued"
    );
};


run_me;
done_testing;

