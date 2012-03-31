#!/perl
use strict;
use warnings;

use Test::More;

use File::Temp qw/ tempdir /;

for my $lib ( 'RRDs',
              'RRD::Simple',
              'App::Wubot::Logger',
              'App::Wubot::Reactor::RRD' ) {

    eval "use $lib";
    plan skip_all => "Failed to load $lib for this test case" if $@;
}

plan 'no_plan';

ok( my $rrd = App::Wubot::Reactor::RRD->new(),
    "Creating a new 'rrd' reactor object"
);

{
    my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
    my $key     = "testcase-key";
    my $field   = "somename";

    my $config = { base_dir  => $tempdir,
                   fields    => { somename => 'GAUGE' },
                   filename  => 'data',
               };

    ok( $rrd->react( { $field => 100, key => $key }, $config ),
        "Calling 'react' with test message"
    );

    ok( -d "$config->{base_dir}/rrd",
        "Checking that rrd subdirectory was created"
    );

    ok( -d "$config->{base_dir}/rrd/$key",
        "Checking that $key subdirectory was created"
    );

    ok( -r "$config->{base_dir}/rrd/$key/data.rrd",
        "Checking that rrd file was created using key field"
    );

    ok( -d "$config->{base_dir}/graphs",
        "Checking that graph directory was created"
    );

    ok( -d "$config->{base_dir}/graphs/$key",
        "Checking that graph subdirectory $key was created"
    );

    ok( -r "$config->{base_dir}/graphs/$key/data-daily.png",
        "Checking that png was created use key field as basename"
    );

    sleep 1;

    ok( $rrd->react( { $field => 200.5, key => $key }, $config ),
        "Calling 'react' with test message"
    );

}

{
    my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
    my $key     = "testcase-key";
    my @fields  = qw( somename1 somename2 );

    my $config = { base_dir  => $tempdir,
                   fields    => { somename1 => 'GAUGE',
                                  somename2 => 'GAUGE',
                              },
                   filename  => 'data2',
               };

    ok( $rrd->react( { 'somename1' => 100, 'somename2' => 200, key => $key }, $config ),
        "Calling 'react' with test message"
    );

    ok( -d "$config->{base_dir}/rrd",
        "Checking that rrd subdirectory was created"
    );

    ok( -d "$config->{base_dir}/rrd/$key",
        "Checking that $key subdirectory was created"
    );

    ok( -d "$config->{base_dir}/graphs",
        "Checking that graph directory was created"
    );

    ok( -d "$config->{base_dir}/graphs/$key",
        "Checking that graph subdirectory $key was created"
    );

    ok( -r "$config->{base_dir}/rrd/$key/data2.rrd",
        "Checking that rrd file was created using key field"
    );

    ok( -r "$config->{base_dir}/graphs/$key/data2-daily.png",
        "Checking that png was created use key field as basename"
    );

}

{
    my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
    my $key     = "testcase-key";
    my @fields  = qw( somename1 somename2 );
    my $time    = time;

    my $config = { base_dir  => $tempdir,
                   fields    => { somename1 => 'GAUGE',
                                  somename2 => 'GAUGE',
                              },
                   heartbeat => 1200,
                   filename  => 'data3',
               };

    ok( $rrd->react( { 'somename1' => 100, 'somename2' => 200, key => $key, lastupdate => $time-1 }, $config ),
        "Calling 'react' with test message"
    );

    my $filename = "$config->{base_dir}/rrd/$key/data3.rrd";

    ok( -r $filename,
        "Checking that rrd file was created using key field"
    );

    my $rrd_simple = RRD::Simple->new( file => $filename );

    is( $rrd_simple->heartbeat( $filename, 'somename1' ),
        1200,
        "Checking that heartbeat was set on rrd file"
    );

    ok( $rrd->react( { 'somename1' => 100, 'somename2' => 200, key => $key, lastupdate => $time }, { %{ $config }, heartbeat => 300 } ),
        "Calling 'react' with test message"
    );

    is( $rrd_simple->heartbeat( $filename, 'somename1' ),
        300,
        "Checking that heartbeat was reset to 300"
    );

}

