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
use App::Wubot::Util::Tivo;


has tivo => (
    is   => 'ro',
    lazy => 1,
    clearer => 'reset_tivo',
    default => sub {

        my $tempdir     = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

        my $tivo = App::Wubot::Util::Tivo->new( { dbfile  => "$tempdir/tasks.sql" } );

        $tivo->{tempdir} = $tempdir;

        return $tivo;
    },
);

my $item = { channel     => 153,
             description => 'Actor Jonah Hill. Copyright Tribune Media Services, Inc.',
             duration    => '30',
             episode     => 'Jonah Hill',
             episode_num => 17030,
             format      => 'video/x-tivo-raw-tts',
             hd          => 'Yes',
             id          => 1,
             link        => 'http://192.168.1.140:80/download/The%20Daily%20Show%20With%20Jon%20Stewart.TiVo?Container=%2FNowPlaying&id=3706588',
             name        => 'The Daily Show With Jon Stewart',
             program_id  => 'EP2930531852',
             recorded    => 1323241200,
             series_id   => 'SH293053',
             size        => 2569,
             tivoid      => 3706588,
             tivo_key    => 12345,
         };

test "update and fetch" => sub {
    my ($self) = @_;

    $self->reset_tivo; # this test requires a fresh one

    ok( $self->tivo->update( $item ),
        "calling update method"
    );

    ok( my $got = $self->tivo->fetch( $item->{tivoid} ),
        "fetching item from database"
    );

    for my $key ( keys %{ $item } ) {

        is( $got->{$key},
            $item->{$key},
            "Checking item field: $key"
        );
    }
};

test "filenames" => sub {
    my ($self) = @_;

    $self->reset_tivo; # this test requires a fresh one

    my $tempdir = $self->tivo->{tempdir};

    my %data = ( directory => "the_daily_show_with_jon_stewart",
                 filename  => "the_daily_show_with_jon_stewart_jonah_hill_3706588",
                 tivo      => "the_daily_show_with_jon_stewart/the_daily_show_with_jon_stewart_jonah_hill_3706588.tivo",
                 mpg       => "the_daily_show_with_jon_stewart/the_daily_show_with_jon_stewart_jonah_hill_3706588.mpg",
             );

    is_deeply( $self->tivo->check_status( $item, $tempdir ),
               \%data,
               "Checking file status"
           );

    system( "mkdir", "$tempdir/the_daily_show_with_jon_stewart" );
    system( "touch", "$tempdir/the_daily_show_with_jon_stewart/the_daily_show_with_jon_stewart_jonah_hill_3706588.tivo" );

    is_deeply( $self->tivo->check_status( $item, $tempdir ),
               { %data, downloaded => 1, errmsg => ".tivo file is too small" },
               "Checking file status"
           );

    system( "touch", "$tempdir/the_daily_show_with_jon_stewart/the_daily_show_with_jon_stewart_jonah_hill_3706588.mpg" );


    is_deeply( $self->tivo->check_status( { %$item }, $tempdir ),
               { %data, downloaded => 1, decoded => 1, errmsg => ".mpg file is too small" },
               "Checking file status"
           );

    unlink( "$tempdir/the_daily_show_with_jon_stewart/the_daily_show_with_jon_stewart_jonah_hill_3706588.tivo" );
    is_deeply( $self->tivo->check_status( { %$item }, $tempdir ),
               { %data, downloaded => 1, decoded => 1, errmsg => ".mpg file is too small" },
               "Checking file status"
           );

    system( "mkdir", "$tempdir/library" );
    system( "mkdir", "$tempdir/library/the_daily_show_with_jon_stewart" );
    system( "touch", "$tempdir/library/the_daily_show_with_jon_stewart/the_daily_show_with_jon_stewart_jonah_hill.mp4" );

    is_deeply( $self->tivo->check_status( { %$item }, $tempdir, "$tempdir/library" ),
               { %data, downloaded => 1, decoded => 1, errmsg => ".mpg file is too small", library => 1 },
               "Checking file status"
           );

    my $newitem = { %$item };
    delete $newitem->{episode};

    is( $self->tivo->check_status( { %$newitem }, $tempdir, "$tempdir/library" )->{library},
        undef,
        "Checking file status"
        );

    system( "touch", "$tempdir/library/the_daily_show_with_jon_stewart/the_daily_show_with_jon_stewart_3706588.mp4" );

    is( $self->tivo->check_status( { %$newitem }, $tempdir, "$tempdir/library" )->{library},
        1,
        "Checking file status"
        );

};

test "monitor" => sub {
    my ($self) = @_;

    $self->reset_tivo; # this test requires a fresh one

    my $tempdir = $self->tivo->{tempdir};

    $self->tivo->update( { %$item, download => 1 } );

    $self->tivo->check_status( $item, $tempdir );

    $self->tivo->monitor();
};


run_me;
done_testing;
