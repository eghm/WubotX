#!/perl
use strict;

use File::Temp qw/ tempdir /;
use Test::More 'no_plan';
use Test::Differences;

BEGIN {
    if ( $ENV{HARNESS_ACTIVE} ) {
        $ENV{WUBOT_SCHEMAS} = "config/schemas";
    }

    $ENV{TZ} = "America/Los_Angeles";
}

use App::Wubot::Logger;
use App::Wubot::Plugin::EmacsOrgMode;
use App::Wubot::Reactor;

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
my $cache_file = "$tempdir/storage.yaml";
my $taskdb = "$tempdir/tasks.sql";

{

    my $reaction = [];
    ok( my $check = App::Wubot::Plugin::EmacsOrgMode->new( { key        => 'EmacsOrgMode-testcase',
                                                             class      => 'App::Wubot::Plugin::EmacsOrgMode',
                                                             cache_file => $cache_file,
                                                             dbfile     => $taskdb,
                                                         } ),
        "Creating a new Emacs Org Mode check instance"
    );

    {
        ok( my $results = $check->check( { config => { directory => 't/org' } } ),
            "Calling check() method again, no changes"
        );

        is( $results->{react}->[0]->{name},
            'file1',
            "Checking name of the first file"
        );

        is( $results->{react}->[1]->{name},
            'file2',
            "Checking name of the second file"
        );

        is( $results->{react}->[2]->{name},
            'file3',
            "Checking name of the third file"
        );

        is( $results->{react}->[3]->{name},
            'file4',
            "Checking name of the third file"
        );

        is( $results->{react}->[0]->{done},
            1,
            "Checking that no incomplete tasks found on file1"
        );

        is( $results->{react}->[1]->{done},
            0,
            "Checking that incomplete tasks found on file2"
        );

        is( $results->{react}->[2]->{done},
            1,
            "Checking that no incomplete tasks found on file3"
        );

        is( $results->{react}->[3]->{done},
            1,
            "Checking that no incomplete tasks found on file4"
        );

        is( $results->{react}->[0]->{color},
            '',
            "Checking that page with no incomplete tasks and no meta color defaults to no color"
        );

        is( $results->{react}->[1]->{color},
            'blue',
            "Checking that page with incomplete tasks defaults to color 'blue'"
        );

        is( $results->{react}->[2]->{color},
            '',
            "Checking that page with complete tasks defaults to no color"
        );

        # is( $results->{react}->[3]->{color},
        #     'asdf',
        #     "Checking that page with meta color defined gets meta color"
        # );

        # is( $results->{react}->[4]->{color},
        #     'qwer',
        #     "Checking that page with meta color defined gets meta color"
        # );

        is( $results->{react}->[5]->{name},
            "file6",
            "checking that file6 was parsed"
        );

        is( $results->{react}->[6]->{title},
            "task 1",
            "Checking that task1 was parsed from file6"
        );

        is( $results->{react}->[6]->{priority},
            "1",
            "Checking that task1 priority is 'b' or '1'"
        );

        is( $results->{react}->[6]->{status},
            "todo",
            "Checking that task1 status is 'todo'"
        );

        is( $results->{react}->[6]->{file},
            "file6",
            "Checking that task1 file is file6"
        );

        is( $results->{react}->[6]->{taskid},
            "file6.task 1",
            "Checking id for task1 in file6"
        );

        is( $results->{react}->[7]->{title},
            "task 2",
            "Checking that task2 was parsed from file6"
        );

        is( $results->{react}->[7]->{status},
            "done",
            "Checking that task2 status is 'todo'"
        );

        is( $results->{react}->[7]->{priority},
            "0",
            "Checking that task1 priority is 'c' or '0'"
        );

        is( $results->{react}->[7]->{file},
            "file6",
            "Checking that task2 file is file6"
        );

        is( $results->{react}->[7]->{scheduled_text},
            "2010-12-24 Fri",
            "Checking that task2 is scheduled for 2010-12-24 Fri"
        );

        is( $results->{react}->[7]->{taskid},
            "file6.task 2",
            "Checking id for task2 in file6"
        );

        is( $results->{react}->[8]->{title},
            "task 3",
            "Checking that task3 was parsed from file6"
        );

        is( $results->{react}->[8]->{status},
            "todo",
            "Checking that task3 status is 'todo'"
        );

        is( $results->{react}->[8]->{priority},
            "-1",
            "Checking that task1 priority is default, -1"
        );

        is( $results->{react}->[8]->{file},
            "file6",
            "Checking that task3 file is file6"
        );

        is( $results->{react}->[8]->{taskid},
            "file6.task 3",
            "Checking id for task3 in file6"
        );

        is( $results->{react}->[8]->{deadline_text},
            "2010-12-21 Tue 12:30",
            "Checking task3 deadline is 2010-12-21 Tue 12:30"
        );

        is( $results->{react}->[9]->{deadline_text},
            '2010-12-22 Wed 12:30',
            "Checking that recurring task time is parsed properly"
        );

         TODO: {
             local $TODO = "broken utime parsing bug";

             is( $results->{react}->[9]->{deadline_utime},
                 1293049800,
                 "Checking that recurring task unix time is parsed properly"
             );

             is( scalar localtime $results->{react}->[9]->{deadline_utime},
                 'Wed Dec 22 12:30:00 2010',
                 "Checking that recurring task local time is parsed properly"
             );
         }


        is( $results->{react}->[10]->{deadline_text},
            '2010-12-22 Wed 12:30',
            "Checking that relative recurring task time is parsed properly"
        );

        is( $results->{react}->[10]->{deadline_recurrence},
            '+1d',
            "Checking deadline recurrence"
        );

        is( $results->{react}->[11]->{scheduled_recurrence},
            '+1w',
            "Checking schedule recurrence"
        );

        is( $results->{react}->[12]->{title},
            'task 7',
            "Checking duration removed from title of task 7"
        );

        is( $results->{react}->[12]->{duration},
            '1h',
            "Checking duration of task 7"
        );

        is( $results->{react}->[13]->{title},
            'task 8',
            "Checking duration removed from title of task 8"
        );

        is( $results->{react}->[13]->{duration},
            '1h30m',
            "Checking duration on task 8"
        );

        is( $results->{react}->[14]->{title},
            'task9',
            "Checking task with progress - title"
        );

        is( $results->{react}->[14]->{progress},
            '0/1',
            "Checking task with progress - progress"
        );

        is ( $results->{react}->[15]->{deadline_text},
             "2011-06-20 Mon",
             "Checking that deadline text is set for task with deadline + schedule"
         );

        is ( $results->{react}->[15]->{scheduled_text},
             "2011-06-17 Fri",
             "Checking that schedule text is set for task with deadline + schedule"
         );


        is( $results->{react}->[17]->{body},
            "  - [ ] foo\n  - [ ] bar\n  - [ ] baz",
            "Checking that state change notes for recurring tasks are not added to body"
        );

        ok( my $results2 = $check->check( { config => { directory => 't/org' },
                                            cache  => $results->{cache}         } ),
            "Calling check() method with lastupdate set to now"
        );

        is_deeply( $results2->{react},
                   [],
                   "Checking that results were blank on the second scan"
               );
    }
}

{

    my $reaction = [];
    ok( my $check = App::Wubot::Plugin::EmacsOrgMode->new( { key        => 'EmacsOrgMode-testcase',
                                                             class      => 'App::Wubot::Plugin::EmacsOrgMode',
                                                             cache_file => "/dev/null",
                                                             dbfile     => $taskdb,
                                                    } ),
        "Creating a new Emacs Org Mode check instance"
    );

    ok( my $results = $check->check( { config => { directory => 't/org/2' } } ),
        "Calling check() method again with new directory"
    );

    is( $results->{react}->[1]->{scheduled_text},
        "2011-06-17 Fri",
        "Checking SCHEDULE when DEADLINE listed first"
    );

    is( $results->{react}->[1]->{deadline_text},
        "2011-06-20 Mon",
        "Checking DEADLINE when DEADLINE listed first"
    );

    is( $results->{react}->[2]->{scheduled_text},
        "2011-06-17 Fri",
        "Checking SCHEDULED when SCHEDULED listed first"
    );

    is( $results->{react}->[2]->{deadline_text},
        "2011-06-20 Mon",
        "Checking DEADLINE when SCHEDULED listed first"
    );



}


{
    my $reaction = [];
    ok( my $check = App::Wubot::Plugin::EmacsOrgMode->new( { key        => 'EmacsOrgMode-testcase',
                                                             class      => 'App::Wubot::Plugin::EmacsOrgMode',
                                                             cache_file => "/dev/null",
                                                             dbfile     => $taskdb,
                                                    } ),
        "Creating a new Emacs Org Mode check instance"
    );

    ok( my $results = $check->check( { config => { directory => 't/org/3' } } ),
        "Calling check() method again with new directory"
    );

    is( $results->{react}->[1]->{taskid},
        "first_task.first line in file is task with two bullet points",
        "checking first line in file is task with two bullet points"
    );

}


{
    my $reaction = [];
    ok( my $check = App::Wubot::Plugin::EmacsOrgMode->new( { key        => 'EmacsOrgMode-testcase',
                                                             class      => 'App::Wubot::Plugin::EmacsOrgMode',
                                                             cache_file => "/dev/null",
                                                             dbfile     => $taskdb,
                                                    } ),
        "Creating a new Emacs Org Mode check instance"
    );

    ok( my $results = $check->check( { config => { directory => 't/org/4' } } ),
        "Calling check() method again with new directory"
    );

    is( $results->{react}->[1]->{taskid},
        "tagged_task.make tea",
        "checking first task id"
    );

    is( $results->{react}->[1]->{taskid},
        "tagged_task.make tea",
        "checking first title"
    );

    is( $results->{react}->[1]->{tag},
        "chores",
        "checking first task tag"
    );

}
