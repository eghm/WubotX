package App::Wubot::Web::TivoWeb;
use strict;
use warnings;

# VERSION

use Mojo::Base 'Mojolicious::Controller';

use POSIX qw(strftime);
use YAML;

use App::Wubot::Util::Colors;
use App::Wubot::SQLite;
use App::Wubot::Util::TimeLength;
use App::Wubot::Util::Tivo;

my $colors       = App::Wubot::Util::Colors->new();
my $timelength   = App::Wubot::Util::TimeLength->new( { space => 1 } );
my $tivoutil     = App::Wubot::Util::Tivo->new();

my $dbfile       = join( "/", $ENV{HOME}, "wubot", "sqlite", "tivo.sql" );
my $sql          = App::Wubot::SQLite->new( { file => $dbfile } );

sub item {
    my $self = shift;

    my $tivoid = $self->stash( 'tivoid' );

    unless ( $tivoid ) {
        die "ERROR: ERROR: no tivoid specified";
    }

    # post
    $self->update_tivo( $tivoid );

    my $item = $tivoutil->fetch( $tivoid );

    my $now = time;

    # get
    $item->{display_color} = $colors->get_color( $item->{color} || 'black' );

    $item->{lastupdate_color} = $timelength->get_age_color( $now - $item->{lastupdate} );

    $item->{recorded_color} = $timelength->get_age_color( abs( $now - $item->{recorded} ) );

    $self->stash( item => $item );

    $self->render( template => 'tivo.item' );
}

sub update_tivo {
    my ( $self, $tivoid ) = @_;

    unless ( $tivoid ) {
        die "ERROR: ERROR: no tivoid specified";
    }

    my $now = time;

    my $changed_flag;

    my $item = { tivoid => $tivoid };

    for my $flag ( qw( color download errmsg downloaded decoded library enqueued curl_cmd tivodecode_cmd ) ) {

        if ( defined $self->param( $flag ) ) {
            $item->{$flag} = $self->param( $flag );
            $changed_flag = 1;
        }

    }

    if ( $changed_flag ) {
        $item->{tivoid} = $tivoid;
        $tivoutil->update( $item );
    }
}

sub list {
    my $self = shift;

    my $now = time;

    my $lastupdate_h;
    $sql->select( { tablename => 'lastupdate',
                    order     => 'lastupdate DESC',
                    limit     => 1,
                    schema    => 'tivo.lastupdate',
                    callback  => sub {
                        $lastupdate_h = shift;
                    },
                } );

    # convert total size to GB
    $lastupdate_h->{size} = $lastupdate_h->{size} / 1000;

    $lastupdate_h->{age} = $timelength->get_human_readable( time - $lastupdate_h->{lastupdate} );

    my $query = { tablename => 'recorded',
                  where     => { lastupdate => $lastupdate_h->{lastupdate} },
                  order     => 'recorded DESC',
                  schema    => 'tivo.recorded',
                  limit     => 500,
              };

    my @items;

    $query->{callback} = sub {
        my $item = shift;

        $item->{link} =~ m|(\d+)$|;
        $item->{tivoid} = $1;

        $item->{display_color} = $colors->get_color( $item->{color} );

        $item->{lastupdate_color} = $timelength->get_age_color( $now - $item->{lastupdate} );
        $item->{recorded_color} = $timelength->get_age_color( $now - $item->{recorded} );

        $item->{tivodl} = $item->{channel} ? "" : "dl";
        $item->{hd}         = $item->{hd} eq "Yes" ? "HD" : "";

        $item->{duration} = $timelength->get_human_readable( $item->{duration} * 60 );

        push @items, $item;
    };

    $sql->select( $query );

    $self->stash( items => \@items );
    $self->stash( headers => [ qw( mark dl enc lib name episode epnum size recorded hd duration updated ) ] );
    $self->stash( info  => $lastupdate_h );

    $self->render( template => 'tivo.list' );

}

1;
