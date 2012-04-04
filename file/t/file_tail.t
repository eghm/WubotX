#!/perl
use strict;

use File::Temp qw/ tempdir /;
use Test::Exception;
use Test::More 'no_plan';

use App::Wubot::Logger;
use App::Wubot::Plugin::FileTail;

my $init = { key        => 'FileTail-testcase',
             class      => 'App::Wubot::Plugin::FileTail',
             cache_file => '/dev/null',
             reactor    => sub {},
         };

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

{
    ok( my $tail = App::Wubot::Plugin::FileTail->new( $init ),
        "Creating new file tail object"
    );

    my $path = "$tempdir/file0.log";

    ok( ! $tail->init( { config => { path => $path } } ),
        "Initializing tail plugin"
    );

    my $results = $tail->check( { config => { path => $path } } );

    is( $results->{react}->[0]->{subject},
        "path not readable: $path",
        "Checking for 'path not readable' reaction when calling check() on file that does not exist"
    );
}

$| = 1;

{
    my $path = "$tempdir/file1.log";

    system( "echo line0 >> $path" );
    system( "echo line0 >> $path" );

    ok( my $tail = App::Wubot::Plugin::FileTail->new( $init ),
        "Creating new file tail object"
    );

    ok( ! $tail->init( { config => { path => $path } } ),
        "Initializing tail plugin"
    );

    ok( $tail->check( { config => { path => $path } } ),
        "Calling reaction on file that exists but has had no writes since open"
    );

    system( "echo line1 >> $path" );
    system( "echo line2 >> $path" );

    my $results1 = $tail->check( { config => { path => $path } } );

    is( $results1->{react}->[0]->{subject},
        'line1',
        "Calling reaction read 'line1'"
    );

    is( $results1->{react}->[1]->{subject},
        'line2',
        "Calling reaction read 'line2'"
    );

    ok( ! $tail->check( { config => { path => $path } } )->{react},
        "Calling reaction after all lines read"
    );

    system( "echo line3 >> $path" );
    system( "echo line4 >> $path" );

    {
        my $results1 = $tail->check( { config => { path => $path } } );

        is( $results1->{react}->[0]->{subject},
            'line3',
            "Calling reaction read 'line3'"
        );

        is( $results1->{react}->[1]->{subject},
            'line4',
            "Calling reaction read 'line4'"
        );

        ok( ! $tail->check( { config => { path => $path } } )->{react},
            "Calling reaction after all lines read"
        );

        system( "echo line5 > $path" );
        system( "echo line6 >> $path" );
    }

    {
        my $results1 = $tail->check( { config => { path => $path } } );

        is( $results1->{react}->[0]->{subject},
            "file was truncated: $path",
            "Checking for 'file was truncated' message"
        );

        is( $results1->{react}->[1]->{subject},
            'line5',
            "Calling reaction read 'line5'"
        );

        is( $results1->{react}->[2]->{subject},
            'line6',
            "Calling reaction read 'line6'"
        );

        ok( ! $tail->check( { config => { path => $path } } )->{react},
            "Calling reaction after no more writes"
        );
    }

    sleep 1;
    unlink( $path );
    system( "echo line7 >> $path" );
    system( "echo line8 >> $path" );

    {
        my $results1 = $tail->check( { config => { path => $path } } );

        is( $results1->{react}->[0]->{subject},
            "file was renamed: $path",
            "Checking for 'file was renamed' reaction"
        );

        is( $results1->{react}->[1]->{subject},
            'line7',
            "Calling reaction read 'line7'"
        );

        is( $results1->{react}->[2]->{subject},
            'line8',
            "Calling reaction read 'line8'"
        );

        ok( ! $tail->check( { config => { path => $path } } )->{results},
            "Calling reaction after no more writes"
        );
    }

    sleep 1; # mv file and re-create
    system( "mv $path $path.old" );
    system( "echo line09 > $path" );
    system( "echo line10 >> $path" );

    {
        my $results1 = $tail->check( { config => { path => $path } } );

        is( $results1->{react}->[0]->{subject},
            "file was renamed: $path",
            "Checking for 'file was renamed' reaction"
        );

        is( $results1->{react}->[1]->{subject},
            'line09',
            "Calling reaction read 'line9'"
        );

        is( $results1->{react}->[2]->{subject},
            'line10',
            "Calling reaction read 'line10'"
        );

        ok( ! $tail->check( { config => { path => $path } } )->{react},
            "Calling reaction after no more writes"
        );
    }

    sleep 1;
    system( "echo line10 > $path" );
    system( "echo line11 >> $path" );

    {
        my $results2 = $tail->check( { config => { path => $path } } );

        is( $results2->{react}->[0]->{subject},
            "file was renamed: $path",
            "checking for 'file was renamed' after truncating file to the same length"
        );

        is( $results2->{react}->[1]->{subject},
            'line10',
            "Calling reaction read 'line10'"
        );

        is( $results2->{react}->[2]->{subject},
            'line11',
            "Calling reaction read 'line11'"
        );

        ok( ! $tail->check( { config => { path => $path } } )->{react},
            "Calling reaction after no more writes"
        );
    }
}
