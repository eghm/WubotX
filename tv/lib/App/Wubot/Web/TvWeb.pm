package App::Wubot::Web::TvWeb;
use strict;
use warnings;

# VERSION

use Mojo::Base 'Mojolicious::Controller';

use Data::ICal;
use Data::ICal::Entry::Event;
use Data::ICal::Entry::Alarm::Audio;
use Date::ICal;
use DateTime;
use Digest::MD5 qw(md5_hex);

use App::Wubot::Logger;
use App::Wubot::Util::TimeLength;
use App::Wubot::Util::Colors;
use App::Wubot::Util::XMLTV;

my $logger = Log::Log4perl::get_logger( __PACKAGE__ );

my $tvdata_file    = join( "/", $ENV{HOME}, "wubot", "sqlite", "tv_data.sql" );
my $xmltv_file     = join( "/", $ENV{HOME}, "wubot", "sqlite", "xmltv.sql" );

my $tv = App::Wubot::Util::XMLTV->new();
my $sqlite_tv_data = App::Wubot::SQLite->new( { file => $tvdata_file } );
my $sqlite_tv      = App::Wubot::SQLite->new( { file => $xmltv_file } );
my $colors         = App::Wubot::Util::Colors->new();
my $timelength     = App::Wubot::Util::TimeLength->new();

my $schemas = { tv_data => { show             => 'VARCHAR(128)',
                             id               => 'INTEGER PRIMARY KEY AUTOINCREMENT',
                             color            => 'VARCHAR(16)',
                             seen             => 'INT',
                             episode          => 'VARCHAR(16)',
                             myscore          => 'INT',
                         },
            };


sub crew {
    my $self = shift;

    my $first = $self->stash( 'first' );
    my $last  = $self->stash( 'last' );

    my %program_ids;

    for my $program_id ( $tv->get_roles( $first, $last ) ) {
        $program_ids{ $program_id }++;
    }

    $self->stash( 'program_ids', [ sort keys %program_ids ] );

    $self->render( template => 'crew' );
}

sub program {
    my $self = shift;

    my $program_id = $self->stash( 'program_id' );

    my ( $program_data ) = $tv->get_program_details( $program_id );

    $program_data->{score} = $tv->get_score( $program_id );
    $program_data->{color} = $tv->get_program_color( $program_id, $program_data->{score} );

    my @crew;
    for my $crew ( $tv->get_program_crew( $program_id ) ) {

        my %other_titles;
        my $title_counts;
      OTHER:
        for my $other_program_id ( $tv->get_roles( $crew->{givenname}, $crew->{surname} ) ) {
            next OTHER if $other_program_id eq $program_id;
            my ( $other_program_details ) = $tv->get_program_details( $other_program_id );

            my $color = $tv->get_program_color( $other_program_id );

            $title_counts->{ $other_program_details->{title} }++;

            $other_titles{ $other_program_details->{title} } = { program_id => $other_program_id,
                                                                 color      => $color,
                                                                 date       => $other_program_details->{date},
                                                                 year       => $other_program_details->{year},
                                                                 rottentomato => $other_program_details->{rottentomato},
                                                                 rottentomato_link => $other_program_details->{rottentomato_link},
                                                                 count      => $title_counts->{ $other_program_details->{title} },
                                                             };
        }

        $crew->{other} = \%other_titles;

        utf8::decode( $crew->{givenname} );
        utf8::decode( $crew->{surname} );

        push @crew, $crew;
    }
    $program_data->{crew}  = \@crew;

    my @episodes;
    for my $episode_id ( $tv->get_episodes( $program_id ) ) {
        my ( $episode_details ) = $tv->get_program_details( $episode_id );
        push @episodes, $episode_details;
    }
    $program_data->{episodes} = \@episodes;

    $self->stash( 'program', $program_data );

    $self->render( template => 'program' );
}

sub seen {
    my $self = shift;

    my $show    = $self->stash('show_id');
    my $episode = $self->stash('episode_num');
    my $seen    = $self->stash('seen');

    $sqlite_tv_data->insert_or_update( 'tv_data',
                                       { show => $show, episode => $episode, seen => $seen },
                                       { show => $show, episode => $episode },
                                       $schemas->{tv_data},
                                   );

    $self->redirect_to( "/tv/schedule" );
}

sub hide {
    my $self = shift;

    my $station_id = $self->stash( 'station_id' );
    my $hide_flag  = $self->stash( 'hide' );

    $logger->info( "Station hide: $station_id => $hide_flag" );

    $tv->hide_station( $station_id, $hide_flag );

    $self->render( template => 'ok' );
}

sub score {
    my $self = shift;

    my $show  = $self->stash('show');
    my $score = $self->stash('score');

    $logger->info( "Setting score for $show to $score" );

    if ( $score eq "D" ) {
        $sqlite_tv_data->update( 'tv_data', { myscore => undef }, [ { show => $show }, { show => $show } ], $schemas->{tv_data} );
        $tv->set_score( $show, undef );
    }
    else {
        $sqlite_tv_data->insert_or_update( 'tv_data', { show => $show, myscore => $score }, { show => $show }, $schemas->{tv_data} );
        $tv->set_score( $show, $score );
    }

    $self->render( template => 'ok' );
}

sub rt {
    my $self = shift;

    my $program_id = $self->stash( 'program_id' );

    $tv->fetch_rt_score( $program_id );

    $self->redirect_to( "/tv/program/$program_id" );
}

sub schedule_crew {
    my $self = shift;

    my $first = $self->stash( 'first' );
    my $last  = $self->stash( 'last' );

    my @program_ids;

    for my $program_id ( $tv->get_roles( $first, $last ) ) {
        push @program_ids, $program_id;
    }

    my @display;
    for my $program ( $tv->get_schedule( { start      => time-300,
                                           program_id => \@program_ids,
                                           all        => 1,
                                           start      => $self->param( 'start'   )  || undef,
                                       } ) ) {
        push @display, $program;
    }

    $self->stash( 'body_data', \@display );

    $self->render( template => 'newtv' );
}

sub schedule {
    my $self = shift;

    my @display;

    for my $program ( $tv->get_schedule( { start   => $self->param( 'start'   ) || undef,
                                           end     => $self->param( 'end'     ) || undef,
                                           limit   => $self->param( 'limit'   ) || 100,
                                           channel => $self->param( 'channel' ) || undef,
                                           score   => $self->param( 'score'   ) || undef,
                                           all     => $self->param( 'all'     ) || undef,
                                           new     => $self->param( 'new'     ) || undef,
                                           hd      => $self->param( 'hd'      ) || undef,
                                           rated   => $self->param( 'rated'   ) || undef,
                                           title   => $self->param( 'title'   ) || undef,
                                           search  => $self->param( 'search'  ) || undef,
                                       } ) ) {

        push @display, $program;

    }

    $self->stash( 'body_data', \@display );

    $self->render( template => 'newtv' );
}

sub schedule_program {
    my $self = shift;

    my @display;

    for my $program ( $tv->get_schedule( { start      => time-300,
                                           program_id => $self->stash('program_id') || undef,
                                           channel    => $self->param( 'channel' )  || undef,
                                           all        => 1,
                                           start      => $self->param( 'start'   )  || undef,
                                       } ) ) {

        push @display, $program;

    }

    $self->stash( 'body_data', \@display );

    $self->render( template => 'newtv' );
}

sub ical {
    my $self = shift;

    my $calendar = Data::ICal->new();

    my $seen;

    # my @programs = $tv->get_schedule( { limit      => 100,
    #                                     score      => 5,
    #                                     start      => -12*60*60,
    #                                 } );

    my @programs = $tv->get_schedule( { limit      => 500,
                                        new        => 1,
                                        score      => 3,
                                        start      => -12*60*60,
                                    } );

    push @programs, $tv->get_schedule( { limit      => 500,
                                         new        => 1,
                                         score      => 4,
                                         start      => -12*60*60,
                                     } );

    for my $program ( @programs ) {

        next if $seen->{ $program->{title} }->{ $program->{start} };
        $seen->{ $program->{title} }->{ $program->{start} } = 1;

        my $duration = 1800;
        if ( $program->{duration} ) {
            $duration = $timelength->get_seconds( $program->{duration} );
        }

        my $dt_start = DateTime->from_epoch( epoch => $program->{start}        );
        my $start    = $dt_start->ymd('') . 'T' . $dt_start->hms('') . 'Z';

        my $dt_end   = DateTime->from_epoch( epoch => $program->{start} + $duration );
        my $end      = $dt_end->ymd('') . 'T' . $dt_end->hms('') . 'Z';

        my $id = join "-", 'TV', md5_hex( $program->{title} ), $program->{start};

        my $title = $program->{title};
        if ( $program->{new} ) {
            $title = "$title NEW";
        }
        if ( $program->{hd} ) {
            $title = "$title HD";
        }
        $title = "[$program->{score}] $title";
        $title = "$title [$program->{channel}]";

        my %event_properties = ( summary     => $title,
                                 dtstart     => $start,
                                 dtend       => $end,
                                 uid         => $id,
                                 description => $program->{description},
                             );

        utf8::encode( $event_properties{summary} );
        utf8::encode( $event_properties{description} );

        my $vevent = Data::ICal::Entry::Event->new();
        $vevent->add_properties( %event_properties );

        my $alarm_time = $program->{start} - 60*15;
        my $valarm_sound = Data::ICal::Entry::Alarm::Audio->new();
        $valarm_sound->add_properties(
            trigger   => [ Date::ICal->new( epoch => $alarm_time )->ical, { value => 'DATE-TIME' } ],
        );
        $vevent->add_entry($valarm_sound);

        $calendar->add_entry($vevent);
    }

    $self->stash( calendar => $calendar->as_string );

    $self->render( template => 'calendar', format => 'ics', handler => 'epl' );
}

sub oldschedule {
    my $self = shift;

    my @shows;

    my $now = time;

    my $count = 1;

    my $where;
    if ( my $search = $self->param( 'search' ) ) {
        $where->{title} = { -like => "%$search%"};
    }
    if ( my $channel = $self->param( 'channel' ) ) {
        $where->{channel} = $channel;
    }
    if ( my $rating = $self->param( 'rating' ) ) {
        $where->{rating} = $rating;
    }
    if ( my $video = $self->param( 'video' ) ) {
        $where->{video} = $video;
    }
    if ( my $new = $self->param( 'new' ) ) {
        $where->{fresh} = 'NEW';
    }

    my $start = $now - 300;
    if ( my $start_param = $self->param( 'start' ) ) {
        $start = $now + $timelength->get_seconds( $start_param );
    }
    $where->{start_utime} = { '>', $start };;

    $sqlite_tv->select( { tablename => 'schedule',
                          where     => $where,
                          order     => [ 'start_utime' ],
                          limit     => $self->param('limit') || 200,
                          callback  => sub { my $show = $_[0];
                                             $show->{count}      = $count++;

                                             $show->{show_esc}   = $show->{title};
                                             $show->{show_esc}   =~ s|\/|_SLASH_|g;
                                             $show->{show_esc}   =~ s|\?|_QUESTION_|g;

                                             $show->{color}      = 'grey';
                                             $show->{date}       =~ s|^(\d\d\d\d)(\d\d)(\d\d)$|$1.$2.$3|g;

                                             if ( $show->{episode_num} ) {
                                                 my $episode = $show->{episode_num};

                                                 if ( $show->{episode_num} =~ m|^([1-9]+)\0(\d\d)$| ) {
                                                     $episode = "s$1e$2";
                                                 }
                                                 elsif ( $episode =~ m|^(\d)(\d\d)$| ) {
                                                     $episode = "s$1e$2";
                                                 }
                                                 elsif ( $episode =~ m|^(\d\d)(\d\d)$| ) {
                                                     if ( $1 < 9 ) {
                                                         $episode = "s$1e$2";
                                                     }
                                                 }

                                                 $show->{episode_num} = $episode;
                                             }

                                             if ( $show->{date} ) {
                                                 if ( $show->{subtitle} || $show->{episode_num} ) {
                                                     $show->{subtitle_date} .= $show->{date};
                                                 }
                                                 else {
                                                     $show->{title_date} .= $show->{date};
                                                 }
                                             }


                                             $show->{start}      = strftime( "%a %l:%M%p", localtime( $show->{start_utime} ) );
                                             $show->{end}        = strftime( "%a %l:%M%p", localtime( $show->{end_utime} ) );

                                             $show->{lastupdate} = strftime( "%m-%d %H:%M", localtime( $show->{lastupdate} ) );


                                             push @shows, $show;
                                         },
                      } );

    my @display;

    my $score_colors = { 1 => 'dark', 2 => 'dark', 3 => 'yellow', 4 => 'orange', 5 => 'pink' };

    my $cache;
    my $score     = $self->param( 'score' );
    my $show_seen = $self->param( 'seen' );
    my $show_all  = $self->param( 'all' );
  SHOW:
    for my $show ( @shows ) {

        $sqlite_tv_data->select( { tablename => 'tv_data',
                                   where     => [ { show => $show->{show_id} }, { show => $show->{title} } ],
                                   limit     => 1,
                                   callback  => sub { my $data = $_[0];
                                                      $show->{'#'} = $data->{myscore};
                                                  },
                               } );

        if ( $score ) {
            next SHOW unless $show->{'#'};
            next SHOW unless $show->{'#'} >= $score;
        }

        if ( $show->{episode_num} ) {
            $sqlite_tv_data->select( { tablename => 'tv_data',
                                       where     => { show => $show->{show_id}, episode => $show->{episode_num} },
                                       limit     => 1,
                                       callback  => sub { my $data = $_[0];
                                                          $show->{seen} = $data->{seen};
                                                      },
                                   } );

        }
        unless ( $show_seen || $show_all ) {
            next SHOW if $show->{seen};
        }

        if ( $show->{'#'} ) {
            $show->{color} = $colors->get_color( $score_colors->{ $show->{'#'} } );
            if ( $show->{'#'} > 2 ) {
                push @display, $show;
            } else {
                if ( $show_all ) {
                    push @display, $show;
                }
            }
        } else {
            push @display, $show;
        }


    }

    $self->stash( 'body_data', \@display );

    $self->render( template => 'tv' );

}

1;

__END__

=head1 NAME

App::Wubot::Web::TvWeb - wubot tv web interface

=head1 CONFIGURATION

   ~/wubot/config/webui.yaml

    ---
    plugins:
      tv:
        '/tv/crew/(.first)/(.last)': 'crew'
        '/tv/program/(.program_id)': 'program'
        '/tv/seen/(.show_id)/(.episode_num)/(.seen)': 'seen'
        '/tv/station/hide/(.station_id)/(.hide)': 'hide'
        '/tv/score/(.show)/(.score)': 'score'
        '/tv/rt/(.program_id)': 'rt'
        '/tv/schedule/crew/(.first)/(.last)': 'schedule_crew'
        '/tv/schedule': 'schedule'
        '/tv/schedule/(.program_id)': 'schedule_program'
        '/tv/ical': 'ical'
        '/tv/oldschedule': 'oldschedule'

=head1 DESCRIPTION

The wubot web interface is still under construction.  There will be
more information here in the future.

TODO: finish docs

=head1 SUBROUTINES/METHODS

=over 8

=item crew

=item program

=item seen

=item hide

=item score

=item rt

=item schedule_crew

=item schedule

=item schedule_program

=item ical

=item oldschedule

=back
