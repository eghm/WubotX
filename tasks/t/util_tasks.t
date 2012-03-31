#!/perl
use strict;
use warnings;

use Test::More tests => 64;
use File::Temp qw/ tempdir /;

BEGIN {
    if ( $ENV{HARNESS_ACTIVE} ) {
        $ENV{WUBOT_SCHEMAS} = "config/schemas";
    }

    $ENV{TZ} = "America/Los_Angeles";
}


use App::Wubot::Logger;
use App::Wubot::Util::Tasks;

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );


ok( my $taskutil = App::Wubot::Util::Tasks->new( { dbfile => "$tempdir/tasks.ql" } ),
    "Creating new taskutil object"
);

my $date_string = '2011-08-22 Mon 10:30';
my $date_utime  = 1314034200;

my $body = "  - [X] do this first
  - [ ] do this second";


{

    my $content = "* Tasks

** TODO [#A] 1h test meeting
   DEADLINE: <$date_string +1w>

$body

";

    my $task1_h = { deadline_utime      => $date_utime,
                    deadline_recurrence => '+1w',
                    deadline_text       => $date_string,
                    duration            => '1h',
                    file                => 'test',
                    priority            => '2',
                    status              => 'todo',
                    taskid              => 'test.test meeting',
                    title               => 'test meeting',
                    type                => 'task',
                    body                => $body,
                    scheduled_text        => undef,
                    scheduled_utime       => undef,
                    scheduled_recurrence  => undef,
                };


    ok( my @results1 = $taskutil->parse_emacs_org_page( "test.org", $content ),
        "Parsing emacs org page content"
    );

    is( scalar @results1,
        1,
        "Checking that one task was found on page"
    );

  TODO: {
        local $TODO = "broken utime parsing bug";

        is_deeply( $results1[0],
                   $task1_h,
                   "Checking that task was parsed properly"
               );
    }

    ok( $taskutil->sync_tasks( "test", $task1_h ),
        "Calling 'sync' method on tasks"
    );

    ok( my @results2 = $taskutil->get_tasks(),
        "Getting a list of tasks from the db"
    );

    is( scalar @results2,
        1,
        "Checking that only 1 task was found in the database"
    );

    for my $param ( keys %{ $task1_h } ) {
        next if $param eq "type";

        is( $results2[0]->{$param},
            $task1_h->{$param},
            "Checking $param on retrieved task"
        );
    }
}


{
    my $content2 = "* Tasks

** TODO [#A] 1h test meeting
   SCHEDULED: <$date_string +1w>

$body

";

    my $task2_h = { scheduled_utime      => $date_utime,
                    scheduled_recurrence => '+1w',
                    scheduled_text       => $date_string,
                    duration             => '1h',
                    file                 => 'test',
                    priority             => '2',
                    status               => 'todo',
                    taskid               => 'test.test meeting',
                    title                => 'test meeting',
                    type                 => 'task',
                    body                 => $body,
                    deadline_text        => undef,
                    deadline_utime       => undef,
                    deadline_recurrence  => undef,
                };

    ok( my @results1 = $taskutil->parse_emacs_org_page( "test.org", $content2 ),
        "Parsing emacs org page content"
    );

    is( scalar @results1,
        1,
        "Checking that one task was found on page"
    );

  TODO: {
        local $TODO = "broken utime parsing bug";

        is_deeply( $results1[0],
                   $task2_h,
                   "Checking that task was parsed properly"
               );
    }

    ok( $taskutil->sync_tasks( "test", $task2_h ),
        "Calling 'sync' method on tasks"
    );

    ok( my @results2 = $taskutil->get_tasks(),
        "Getting a list of tasks from the db"
    );

    is( scalar @results2,
        1,
        "Checking that only 1 task was found in the database"
    );

    for my $param ( keys %{ $task2_h } ) {
        next if $param eq "type";

        is( $results2[0]->{$param},
            $task2_h->{$param},
            "Checking $param on retrieved task"
        );
    }
}

{

    my $due_utime = time + 60*10;
    my $due_string = scalar localtime $due_utime;

    my $content = "* Tasks

** TODO [#A] 1h different test meeting
   SCHEDULED: <$due_string +1w>

$body

";

    my $task_h = { scheduled_utime      => $due_utime,
                    scheduled_recurrence => '+1w',
                    scheduled_text       => $due_string,
                    duration             => '1h',
                    file                 => 'test',
                    priority             => '2',
                    status               => 'todo',
                    taskid               => 'test.different test meeting',
                    title                => 'different test meeting',
                    type                 => 'task',
                    body                 => $body,
                    deadline_text        => undef,
                    deadline_utime       => undef,
                    deadline_recurrence  => undef,
                };

    ok( $taskutil->sync_tasks( "test", $task_h ),
        "Calling 'sync' method on tasks"
    );

    ok( my @results = $taskutil->get_tasks(),
        "Getting a list of tasks from the db"
    );

    is( scalar @results,
        1,
        "Checking that only 1 task was found in the database"
    );

    for my $param ( keys %{ $task_h } ) {
        next if $param eq "type";

        is( $results[0]->{$param},
            $task_h->{$param},
            "Checking $param on retrieved task"
        );
    }

    my @results2 = $taskutil->check_schedule();

    delete $results2[0]->{lastupdate};
    delete $results2[0]->{subject};
    delete $task_h->{type};
    delete $task_h->{lastupdate};

    $task_h->{color} = 'yellow';
    $task_h->{id}    = 2;
    $task_h->{tag}   = undef;

    is_deeply( $results2[0],
               $task_h,
               "Checking get_schedule() method"
           );

}

{
    my $content = "* Tasks

** TODO [#A] different test meeting

$body

";

    my $task_h = { file                 => 'test',
                   priority             => '2',
                   status               => 'todo',
                   taskid               => 'test.different test meeting',
                   title                => 'different test meeting',
                   type                 => 'task',
                   body                 => $body,
                   deadline_text        => undef,
                   deadline_utime       => undef,
                   deadline_recurrence  => undef,
                   scheduled_text       => undef,
                   scheduled_utime      => undef,
                   scheduled_recurrence => undef,
                   duration             => undef,
               };

    ok( my @results1 = $taskutil->parse_emacs_org_page( "test.org", $content ),
        "Parsing emacs org page content"
    );

    ok( $taskutil->sync_tasks( "test", $results1[0] ),
        "Calling 'sync' method on tasks"
    );

    ok( my @results2 = $taskutil->get_tasks(),
        "Getting a list of tasks from the db"
    );

    is( scalar @results2,
        1,
        "Checking that only 1 task was found in the database"
    );

    delete $results2[0]->{lastupdate};
    delete $results2[0]->{subject};
    delete $task_h->{type};

    $task_h->{color} = 'yellow';
    $task_h->{id}    = 2;
    $task_h->{count} = 1;
    $task_h->{tag}   = 'null';

    is_deeply( $results2[0],
               $task_h,
               "Checking that results match original task"
           );

}
