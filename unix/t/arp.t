#!/perl
use strict;

use File::Temp qw/ tempdir /;
use Test::More 'no_plan';
use Test::Differences;

use App::Wubot::Logger;
use App::Wubot::Plugin::Arp;

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
my $cache_file = "$tempdir/storage.yaml";


{
    ok( my $check = App::Wubot::Plugin::Arp->new( { class      => 'App::Wubot::Plugin::Arp',
                                                    cache_file => $cache_file,
                                                    key        => 'Arp-testcase',
                                                    reactor    => sub {},
                                                } ),
        "Creating a new OSX Idle check instance"
    );

    ok( my $results = $check->check( {} ),
        "Calling check() method"
    );

    for my $react ( @{ $results->{react} } ) {
        ok( $react->{ip},
            "Checking that entry in arp table has an ip address: $react->{ip}"
        );

        ok( $react->{mac},
            "Checking that entry in arp table has a mac address: $react->{mac}"
        );

        ok( $react->{name},
            "Checking that entry in arp table has a name: $react->{name}"
        );
    }

    my $test_macs = { 'a0:b1:c2:d3:e4:f5' => 'a0:b1:c2:d3:e4:f5',
                      '00:14:7b:49:b9:00' => '00:14:7b:49:b9:00',
                      '0:14:7b:49:b9:00'  => '00:14:7b:49:b9:00',
                      '00:14:7b:49:b9:0'  => '00:14:7b:49:b9:00',
                      '00:14:b:49:b9:00'  => '00:14:0b:49:b9:00',
                  };

    for my $mac ( keys %{ $test_macs } ) {
        my $expected = $test_macs->{$mac};

        is( $check->_standardize_mac( $mac ),
            $expected,
            "Checking standardized mac $mac is $expected"
        );
    }

}
