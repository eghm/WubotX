package App::Wubot::Util::XMLTV;
use Moose;

# VERSION

use Benchmark;
use Capture::Tiny qw/capture/;
use Date::Manip;
use LWP::Simple;
use POSIX qw(strftime);
use XML::Twig;

use App::Wubot::Logger;
use App::Wubot::SQLite;
use App::Wubot::Util::TimeLength;

=head1 NAME

App::Wubot::Util::XMLTV - utility method for dealing with XMLTV data


=head1 SYNOPSIS

    use App::Wubot::Util::XMLTV;

=head1 DESCRIPTION

This library takes care of fetching XMLTV data using tv_grab_na_dd,
parsing it using XML::Twig, and inserting it into a SQLite database.
It also provides a number of methods to make it easy to retrieve data
from the database and to display it in the web interface.

This plugin is not yet documented.

TODO: write more docs here!

=cut

has 'db' => ( is => 'ro',
              isa => 'App::Wubot::SQLite',
              lazy => 1,
              default => sub {
                  my $self = shift;
                  return App::Wubot::SQLite->new( { file => join( "/", $ENV{HOME}, "wubot", "sqlite", "xml_tv.sql" ) } );
              },
          );

has 'dbfile' => ( is => 'ro',
                  isa => 'Str',
                  lazy => 1,
                  default => sub {
                      my $self = shift;
                      return $self->schemas->{files}->{tv};
                  },
              );

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

has 'timelength' => ( is => 'ro',
                      isa => 'App::Wubot::Util::TimeLength',
                      lazy => 1,
                      default => sub {
                          return App::Wubot::Util::TimeLength->new();
                      },
                  );

has 'cache'        => ( is => 'ro',
                        isa => 'HashRef',
                        lazy => 1,
                        default => sub { {} },
                    );


has 'score_colors' => ( is => 'ro',
                        isa => 'HashRef',
                        lazy => 1,
                        default => sub {
                            return { 0 => 'gray',
                                     1 => '#770000',
                                     2 => '#666699',
                                     3 => '#999900',
                                     4 => '#AA7700',
                                     5 => '#FF33FF',
                                 };

                        },
                    );

=head1 SUBROUTINES/METHODS

=over 8

=item $obj->fetch_process_data();

TODO: documentation this method

=cut

sub fetch_process_data {
    my ( $self, $tmpfile ) = @_;

    $self->logger->info( "Deleting schedule data older than 4 weeks" );
    my $oldest_date = time - 60*60*24*7*4;
    $self->db->delete( "schedule", { start => { "<" => $oldest_date } }, "tv" );
    $self->logger->info( "Deleting schedule data complete" );

    my $count = 0;

    for my $day ( 0 .. 14 ) {
        $self->logger->info( "Fetching data for day $day" );

        my $command = "/usr/local/bin/tv_grab_na_dd -dd-data $tmpfile --days 1 --offset $day --download-only";
        #print "COMMAND: $command\n";
        system( $command );

        $self->logger->info( "Processing data" );

        my $start = new Benchmark;

        my ($stdout, $stderr) = capture {
            $count += $self->process_data( $tmpfile );
        };

        for my $line ( split /\n/, $stderr ) {
            next if $line =~ m|are not unique|;
            next if $line =~ m|constraint failed|;

            $self->logger->warn( "> $line" );
        }

        $self->logger->info( $stdout );

        my $end = new Benchmark;
        my $diff = timediff( $end, $start );
        $self->logger->info( "Time taken was ", timestr( $diff, 'all' ), " seconds" );

    }

    $self->logger->info( "DONE PROCESSING XMLTV DATA" );

    return $count;
}

=item $obj->process_data();

TODO: documentation this method

=cut

sub process_data {
    my ( $self, $xmlfile ) = @_;

    my $now = time;
    my $count = 0;

    my $twig=XML::Twig->new(
        twig_handlers => 
            { station     => sub {

                  my $station = { station_id => $_->att( 'id' ),
                                  callsign   => $_->field( 'callSign' ),
                                  name       => $_->field( 'name' ),
                                  affiliate  => $_->field( 'affiliate' ),
                                  fccnumber  => $_->field( 'fccChannelNumber' ),
                                  lastupdate => $now,
                              };

                  #$self->logger->debug( "STATION: $station->{station_id} => $station->{callsign} => $station->{name}" );

                  $self->db->insert( 'station',
                                     $station,
                                     "tv"
                                 );

                  $count++;

              },
              lineup      => sub {

                  for my $child ( $_->find_by_tag_name( 'map' ) ) {

                      my $entry = { lineup_id  => $_->att('id'),
                                    channel    => $child->att('channel'),
                                    station_id => $child->att('station'),
                                    lastupdate => $now,
                                };

                      #$self->logger->debug( "LINEUP: $entry->{station_id} => $entry->{station_id} => $entry->{channel}" );

                      $self->db->insert( 'lineup',
                                         $entry,
                                         "tv"
                                     );

                      $count++;
                  }

              },
              schedule     => sub {

                  my $start_time = UnixDate( ParseDate( $_->att('time') ), "%s" );

                  my $entry = { program_id  => $_->att('program'),
                                station_id  => $_->att('station'),
                                start       => $start_time,
                                duration    => $_->att('duration' ),
                                new         => $_->att('new'),
                                cc          => $_->att('closeCaptioned'),
                                stereo      => $_->att('stereo'),
                                tv_rating   => $_->att('tvRating'),
                                dolby       => $_->att('dolby'),
                                hd          => $_->att('hdtv'),
                                lastupdate  => $now,
                            };

                  $self->db->insert( 'schedule',
                                     $entry,
                                     "tv"
                                 );

                  $count++;

              },
              program     => sub {

                  my $entry = { program_id  => $_->att('id'),
                                title       => $_->field('title'),
                                subtitle    => $_->field('subtitle'),
                                description => $_->field('description'),
                                show_type   => $_->field('showType'),
                                series_id   => $_->field('series'),
                                episode_id  => $_->field('syndicatedEpisodeNumber'),
                                date        => $_->field('originalAirDate'),
                                mpaa_rating => $_->field('mpaaRating'),
                                stars       => $_->field('starRating'),
                                runtime     => $_->field('runTime'),
                                year        => $_->field('year'),
                                color       => $_->field('colorCode'),
                                lastupdate  => $now,
                            };

                  my $score_id = $entry->{program_id};
                  if ( $score_id =~ m|^EP| ) {
                      $score_id =~ s|^EP|SH|;
                      $score_id =~ s|....$|0000|;
                  }
                  $entry->{score_id} = $score_id;

                  $self->db->insert_or_update( 'program',
                                               $entry,
                                               { program_id => $entry->{program_id} },
                                               "tv"
                                           );

                  $count++;

              },
              crew         => sub {

                  for my $child ( $_->find_by_tag_name( 'member' ) ) {

                      my $entry = { program_id    => $_->att( 'program' ),
                                    role          => $child->field( 'role' ),
                                    givenname     => $child->field( 'givenname' ),
                                    surname       => $child->field( 'surname' ),
                                    lastupdate    => $now,
                                };

                      $self->db->insert( 'crew',
                                         $entry,
                                         "tv"
                                     );

                      $count++;
                  }
              },
              programGenre  => sub {

                  for my $child ( $_->find_by_tag_name( 'genre' ) ) {

                      my $entry = { program_id   => $_->att( 'program' ),
                                    genre        => $child->field( 'class' ),
                                    relevance    => $child->field( 'relevance' ),
                                    lastupdate   => $now,
                                };

                      $self->db->insert( 'genre',
                                         $entry,
                                         "tv"
                                     );

                      $count++;
                  }

              },
          },
        pretty_print => 'indented',
    );

    $twig->parsefile( $xmlfile );

    return $count;

}

=item $obj->get_data();

TODO: documentation this method

=cut

sub get_data {
    my ( $self, $table, $where, $key, $order ) = @_;

    my @data;

    my $fields = '*';
    if ( $key ) { $fields = $key }

    $self->db->select( { tablename => $table,
                         where     => $where,
                         fields    => $fields,
                         order     => $order,
                         schema    => "tv",
                         callback  => sub {
                             my $entry = shift;

                             if ( $key ) {
                                 push @data, $entry->{ $key };
                             }
                             else {
                                 push @data, $entry;
                             }
                         },
                     } );

    return @data;
}

=item $obj->get_series_id();

TODO: documentation this method

=cut

sub get_series_id {
    my ( $self, $name ) = @_;

    my %ids;

    $self->db->select( { tablename => 'program',
                         where     => { title => $name },
                         fields    => 'series_id',
                         schema    => 'tv',
                         callback  => sub {
                             my $entry = shift;
                             $ids{ $entry->{series_id} }++;
                         },
                     } );

    my @ids = sort keys %ids;

    return @ids;
}

=item $obj->get_program_id();

TODO: documentation this method

=cut

sub get_program_id {
    my ( $self, $name, $like ) = @_;

    my %ids;

    my $search;
    if ( $like ) {
        $search->{title} = { like => "%$name%" };
    }
    else {
        $search->{title} = $name;
    }

    $self->db->select( { tablename => 'program',
                         fields    => 'program_id',
                         where     => $search,
                         schema    => 'tv',
                         callback  => sub {
                             my $entry = shift;
                             $ids{ $entry->{program_id} }++;
                         },
                     } );

    my @ids = sort keys %ids;

    return @ids;
}

=item $obj->get_episodes();

TODO: documentation this method

=cut

sub get_episodes {
    my ( $self, $showid ) = @_;

    if ( length $showid == 14 ) {
        $showid =~ s|....$||;
    }
    if ( $showid =~ m|^SH0| ) {
        $showid =~ s|^SH|EP|;
    }

    my %ids;

    $self->db->select( { tablename => 'program',
                         fields    => 'program_id',
                         where     => { program_id => { 'LIKE' => "$showid%" } },
                         schema    => 'tv',
                         callback  => sub {
                             my $entry = shift;
                             $ids{ $entry->{program_id} }++;
                         },
                     } );

    my @ids = sort keys %ids;

    return @ids;
}

=item $obj->get_program_details();

TODO: documentation this method

=cut

sub get_program_details {
    my ( $self, $program_id ) = @_;

    my @details;

    if ( length( $program_id ) == 10 ) {
        $program_id .= "0000";
    }

    $self->db->select( { tablename => 'program',
                         where     => { program_id => $program_id },
                         schema    => 'tv',
                         callback  => sub {
                             my $entry = shift;

                             utf8::decode( $entry->{title} );
                             utf8::decode( $entry->{description} );

                             if ( $entry->{program_id} =~ m|^EP| ) {
                                 $entry->{ep_id} = $entry->{program_id};
                                 $entry->{program_id} =~ s|^EP|SH|;
                                 $entry->{program_id} =~ s|....$||;
                             }

                             if ( $entry->{year} && ! $entry->{date} ) {
                                 $entry->{date} = $entry->{year};
                             }

                             ( $entry->{rottentomato}, $entry->{rottentomato_link} )
                                 = $self->get_rt( $entry->{program_id}, $entry->{title} );

                             push @details, $entry;
                         },
                     } );

    return @details;
}

=item $obj->get_station();

TODO: documentation this method

=cut

sub get_station {
    my ( $self, $where ) = @_;

    my @details;

    $self->db->select( { tablename => 'station',
                         where     => $where,
                         schema    => 'tv',
                         callback  => sub {
                             my $entry = shift;
                             push @details, $entry;
                         },
                     } );

    return @details;
}

=item $obj->get_program_crew();

TODO: documentation this method

=cut

sub get_program_crew {
    my ( $self, $program_id ) = @_;

    if ( length( $program_id ) == 10 ) {
        $program_id .= "0000";
    }

    return $self->get_data( 'crew', { program_id => $program_id } );
}

=item $obj->get_roles();

TODO: documentation this method

=cut

sub get_roles {
    my ( $self, $first, $last ) = @_;

    my @programs;

    for my $program ( $self->get_data( 'crew', { givenname => $first, surname => $last }, 'program_id' ) ) {

        push @programs, $program;
    }

    @programs = sort @programs;

    return @programs;
}

=item $obj->get_program_genres();

TODO: documentation this method

=cut

sub get_program_genres {
    my ( $self, $program_id ) = @_;

    return $self->get_data( 'genre', { program_id => $program_id }, 'genre', 'relevance' );
}

=item $obj->get_channel();

TODO: documentation this method

=cut

sub get_channel {
    my ( $self, $station_id ) = @_;

    return ( $self->get_data( 'lineup', { station_id => $station_id }, 'channel' ) )[0];
}

=item $obj->get_station_id();

TODO: documentation this method

=cut

sub get_station_id {
    my ( $self, $channel ) = @_;

    my ( $station_id ) = $self->get_data( 'lineup', { channel => $channel }, 'station_id' );

    return $station_id;
}

=item $obj->hide_station();

TODO: documentation this method

=cut

sub hide_station {
    my ( $self, $station_id, $hide ) = @_;

    $self->db->update( 'station',
                       { hide => $hide, lastupdate => time },
                       { station_id => $station_id },
                       'tv'
                   );
}

=item $obj->is_station_hidden();

TODO: documentation this method

=cut

sub is_station_hidden {
    my ( $self, $station_id ) = @_;

    my ( $hidden_flag ) = $self->get_data( 'station', { station_id => $station_id }, 'hide' );

    return $hidden_flag;
}

=item $obj->set_score();

TODO: documentation this method

=cut

sub set_score {
    my ( $self, $program_id, $score ) = @_;

    if ( length( $program_id ) == 10 ) {
        $program_id .= "0000";
    }

    if ( $score ) {
        $self->db->insert_or_update( 'score',
                                     { score => $score, program_id => $program_id, lastupdate => time },
                                     { program_id => $program_id },
                                     'tv'
                                 );
    }
    else {
        $self->db->delete( 'score',
                           { program_id => $program_id },
                           'tv'
                       );
    }
}

=item $obj->get_program_color();

TODO: documentation this method

=cut

sub get_program_color {
    my ( $self, $program_id, $score ) = @_;

    unless ( $score ) {
        $score = $self->get_score( $program_id );
    }

    return $self->score_colors->{ $score || 0 };

}

=item $obj->clean_program_id();

TODO: documentation this method

=cut

sub clean_program_id {
    my ( $self, $program_id ) = @_;

    if ( $program_id =~ m|^EP| ) {
        $program_id =~ s|^EP|SH|;
        $program_id =~ s|....$||;
    }
    if ( length( $program_id ) == 10 ) {
        $program_id .= "0000";
    }

    return $program_id;
}

=item $obj->get_score();

TODO: documentation this method

=cut

sub get_score {
    my ( $self, $program_id ) = @_;

    $program_id = $self->clean_program_id( $program_id );

    my $score;

    eval {
        ( $score ) = $self->get_data( 'score',
                                      { program_id => $program_id },
                                      'score'
                                  );
    };

    return $score || 0;
}

=item $obj->get_schedule();

TODO: documentation this method

=cut

sub get_schedule {
    my ( $self, $options ) = @_;

    my $where;

    if ( $options->{start} ) {
        my $seconds = $self->timelength->get_seconds( $options->{start} );
        $where->{start}->{'>'} = time + $seconds;
    }
    elsif ( $options->{start_utime} ) {
        $where->{start}->{'>'} = $options->{start_utime};
    }
    else {
        $where->{start}->{'>'} = time - 300;
    }

    if ( $options->{end} ) {
        my $seconds = $self->timelength->get_seconds( $options->{end} );
        $where->{start}->{'<'} = time + $seconds;
    }

    if ( $options->{channel} && ! $options->{all} ) {
        $where->{'lineup.channel'} = $options->{channel};
    }
    if ( $options->{program_id} ) {
        $where->{'schedule.program_id'} = $options->{program_id};
    }
    if ( $options->{new} ) {
        $where->{'schedule.new'} = 'true';
    }

    if ( $options->{score} ) {
        $where->{score} = { '>=' => $options->{score} };
    }
    elsif ( ! $options->{all} ) {
        my $is_null = "is null";
        $where->{score} = [ { '>' => 2 }, \$is_null ];
    }
    unless ( $options->{all} ) {
        my $is_not_null = "IS NULL";
        $where->{'station.hide'} = \$is_not_null;
    }

    if ( $options->{hd} ) {
        $where->{'schedule.hd'} = 'true';
    }
    if ( $options->{title} ) {
        $where->{'schedule.program_id'} = [ $self->get_program_id( $options->{title} ) ];
    }
    elsif ( $options->{search} ) {
        $where->{'schedule.program_id'} = [ $self->get_program_id( $options->{search}, 1 ) ];
    }

    my @entries;
    my $count = 0;

    # todo: why are a tiny amount of items duplicated?
    my $seen;

    $self->db->select( { tablename => 'schedule left join program on schedule.program_id = program.program_id left join score on program.score_id = score.program_id left join lineup on schedule.station_id = lineup.station_id left join station on schedule.station_id = station.station_id',
                         where     => $where,
                         limit     => $options->{limit} || 100,
                         order     => 'start',
                         fields    => 'program.program_id as x_program_id, station.station_id as x_station_id, schedule.lastupdate as lastupdate, *',
                         schema    => 'tv.schedule',
                         callback  => sub {
                             my $entry = shift;

                             $count++;

                             $entry->{program_id} = $entry->{x_program_id};
                             $entry->{station_id} = $entry->{x_station_id};

                             return if $seen->{ $entry->{program_id} }->{ $entry->{station_id} }->{ $entry->{start} };
                             $seen->{ $entry->{program_id} }->{ $entry->{station_id} }->{ $entry->{start} } = 1;

                             my ( $program_data ) = $self->get_program_details( $entry->{program_id} );
                             return if $program_data->{hide};
                             for my $key ( keys %{ $program_data } ) {
                                 $entry->{ $key } = $program_data->{ $key };
                             }

                             #$entry->{channel} = $self->get_channel( $station_data->{station_id} );

                             #$entry->{score} = $self->get_score( $entry->{program_id} );

                             $entry->{score} = 0 unless $entry->{score};

                             if ( $entry->{score} && ! $options->{all} ) {

                                 if ( $options->{score} ) {
                                     return unless $entry->{score} >= $options->{score};
                                 }
                                 else {
                                     # default min score, if a score is not assigned
                                     return unless $entry->{score} >= 3;
                                 }
                             }
                             else {
                                 return if $options->{score};
                             }

                             if ( $options->{rated} ) {
                                 return unless $entry->{mpaa_rating} eq $options->{rated};
                             }

                             $entry->{color} = $self->get_program_color( $entry->{program_id}, $entry->{score} );

                             $entry->{start_time}  = strftime( "%a %d %l:%M%p", localtime( $entry->{start} ) );

                             $entry->{lastupdate}  = strftime( "%m-%d.%H:%M", localtime( $entry->{lastupdate} ) );

                             $entry->{runtime}  = $entry->{duration} || $entry->{runtime};
                             $entry->{runtime}  =~ s|^PT0||;
                             $entry->{runtime}  =~ s|^0H||;
                             $entry->{runtime}  = lc( $entry->{runtime} );
                             $entry->{duration} = $entry->{runtime};

                             $entry->{count} = $count;

                             push @entries, $entry;
                         },
                     } );

    return @entries;
}

=item $obj->get_rt();

TODO: documentation this method

=cut

sub get_rt {
    my ( $self, $program_id, $title ) = @_;

    # only look for RT scores for movies
    return unless $program_id =~ m|^MV|;

    if ( $self->cache->{rt}->{ $program_id } ) {
        return @{ $self->cache->{rt}->{ $program_id } };
    }

    my ( $rt_data ) = $self->get_data( 'rottentomato', { program_id => $program_id } );

    if ( ! $rt_data && $title ) {
        ( $rt_data ) = $self->get_data( 'rottentomato', { title => $title } );

        if ( $rt_data ) {
            $rt_data->{program_id} = $program_id;
            $rt_data->{lastupdate} = time;
            $self->db->update( 'rottentomato',
                               $rt_data,
                               { title => $title },
                               'tv'
                           );
        }
    }


    if ( $rt_data->{link} ) {
        $rt_data->{link} = "http://www.rottentomatoes.com$rt_data->{link}";
    }

    $self->cache->{rt}->{ $program_id } = [ $rt_data->{percent}, $rt_data->{link}, $rt_data->{synopsis} ];

    return @{ $self->cache->{rt}->{ $program_id } };
}

=item $obj->fetch_rt_score();

TODO: documentation this method

=cut

sub fetch_rt_score {
    my ( $self, $program_id, $program_title, $program_year ) = @_;

    my $results;

    unless ( $program_title && $program_year ) {
        my ( $program_data ) = $self->get_program_details( $program_id );
        $program_title = $program_data->{title};
        $program_year  = $program_data->{year};

        $results->{program_id} = $program_id;
    }

    my $search_results = $self->get_rt_search_results( $program_title );

  TITLE:
    for my $search_title ( keys %{ $search_results } ) {

        # check that titles match
        next TITLE unless lc( $search_title ) eq lc( $program_title );

        my $num_keys = scalar keys %{ $search_results->{ $search_title } };

        # if there are multiple years, require that one match exactly.
        # If there's only one year, we'll go with that--otherwise we
        # might miss some that have years off by 1 in different systems.
        my $year_match;
        if ( $num_keys > 1 ) {

          YEAR:
            for my $year ( keys %{ $search_results->{ $search_title } } ) {
                #print "Checking $program_title from '$year' against '$program_year'\n";
                next YEAR unless $year == $program_year;
                $year_match = $year;
                #print "\tMatch!\n";
            }

            next TITLE unless $year_match;
        }
        else {
            ( $year_match ) = keys %{ $search_results->{ $search_title } };
        }

        $results->{link}  = $search_results->{ $search_title }->{ $year_match };
        $results->{title} = $program_title;

    }

    unless ( $results->{link} ) {
        warn "ERROR: NO LINK FOUND: TITLE=$program_title!";
        return;
    }

    print "GOT: LINK:$results->{link} TITLE:$results->{title}\n";

    my $review_content = get( "http://www.rottentomatoes.com/$results->{link}" );

    if ( $review_content ) {
        if ( $review_content =~ m|\<span id\=\"all-critics-meter\".*?\>(\d+)\<\/span\>| ) {
            $results->{percent} = $1;
        }

        if ( $review_content =~ m|Runtime\:.*?property\=\"v\:runtime\".*?\>(.*?)\<|s ) {
            $results->{runtime} = $1;
        }

        if ( $review_content =~ m|Synopsis\:.*?movie_synopsis_all\".*?>(.*?)\<\/span\>|s ) {
            $results->{synopsis} = $1;
        }
    }

    $results->{lastupdate} = time;

    if ( $program_id ) {
        $self->db->insert_or_update( 'rottentomato',
                                     $results,
                                     { program_id => $program_id },
                                     'tv'
                                 );

        # update the cache
        delete $self->cache->{rt}->{ $program_id };
    }

    return $results;
}

=item $obj->get_rt_search_results();

TODO: documentation this method

=cut

sub get_rt_search_results {
    my ( $self, $title ) = @_;

    $title    =~ s| |\+|g;

    my $url = "http://www.rottentomatoes.com/search/full_search.php?search=$title";
    print "RT: $url\n";

    my $content = get( $url );

    my $results;

  SECTION:
    for my $section ( split /\<a href\=/, $content ) {

        next SECTION unless $section =~ m|\"(.*?)\".*?\>\s*(.*?)\s*\<.*?\<p\>\<strong\>(\d\d\d\d)\<\/strong\>\<\/p\>|s;

        my ( $link, $title, $year ) = ( $1, $2, $3 );

        # ignore non-movie links
        next unless $link =~ m|^\/m\/|;

        $title = lc( $title );

        $results->{ $title }->{ $year } = $link;


    }

    return $results;

}

__PACKAGE__->meta->make_immutable;

1;

__END__

=back
