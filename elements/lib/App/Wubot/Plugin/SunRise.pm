package App::Wubot::Plugin::SunRise;
use Moose;

# VERSION

use Astro::Sunrise;
use Date::Manip;
use POSIX qw(strftime);

use App::Wubot::Logger;
use App::Wubot::Util::TimeLength;

has 'timelength' => ( is => 'ro',
                      isa => 'App::Wubot::Util::TimeLength',
                      lazy => 1,
                      default => sub { return App::Wubot::Util::TimeLength->new(); },
                  );

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};

    my $now  = time;

    my $message = { coalesce => $self->key };

    # if the next sunrise/sunset event listed in the cache is in the
    # future, then use that date instead of re-calculating
    if ( $cache->{next_utime} && $cache->{next_utime} > $now ) {

        $message = $inputs->{cache};
        delete $message->{lastupdate};

        $message->{cache_remaining} = $cache->{next_utime} - $now;

        my $diff = $message->{next_utime} - $now;
        $message->{diff} = $diff;

        my $mins = int( $diff / 60 );

        # send a message when there is a round number of hours before
        # the next sunrise/sunset
        return unless $mins % 60 == 0;

        my $diff_time = $self->timelength->get_human_readable( $mins*60 );
        $message->{subject} = "$cache->{next} in $diff_time";

        return { react => $message };
    }


    my $config = $inputs->{config};

    $message->{sunrise} = sun_rise( $config->{longitude}, $config->{latitude} );
    $message->{sunset}  = sun_set(  $config->{longitude}, $config->{latitude} );

    my $dst_flag = ( localtime() )[-1];

    my $time = strftime( "%H:%M", localtime( $now ) );

    # if after sunset, get next sunrise time
    if ( $time gt $message->{sunset} ) {

        $message->{after_sunset} = 1;
        $message->{sunrise} = sun_rise( $config->{longitude}, $config->{latitude}, 0, 1 );

        $message->{next}       = 'sunrise';
        $message->{next_utime} = UnixDate( ParseDate( "tomorrow $message->{sunrise}" ), "%s" );
        if ( $dst_flag ) { $message->{next_utime} -= 3600 }
        $message->{next_until} = $self->timelength->get_human_readable( $message->{next_utime} - $now );

        $message->{subject}    = "$message->{next} in $message->{next_until}";
    }
    elsif ( $time lt $message->{sunrise} ) {
        $message->{before_sunrise} = 1;

        $message->{next}       = 'sunrise';
        $message->{next_utime} = UnixDate( ParseDate( $message->{sunrise} ), "%s" );
        if ( $dst_flag ) { $message->{next_utime} -= 3600 }
        $message->{next_until} = $self->timelength->get_human_readable( $message->{next_utime} - $now );

        $message->{subject}    = "$message->{next} in $message->{next_until}";
    }
    else {
        $message->{daytime} = 1;

        $message->{next}       = 'sunset';
        $message->{next_utime} = UnixDate( ParseDate( $message->{sunset} ), "%s" );
        if ( $dst_flag ) { $message->{next_utime} -= 3600 }
        $message->{next_until} = $self->timelength->get_human_readable( $message->{next_utime} - $now );

        $message->{subject}    = "$message->{next} in $message->{next_until}";
    }

    $message->{hours_until} = ( $message->{next_utime} - $now ) / 3600;

    return { react => $message, cache => $message };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::SunRise - monitor the sunrise and sunset times


=head1 SYNOPSIS

  ~/wubot/config/plugins/SunRise/home.yaml

  ---
  longitude: -123.4567890
  latitude: 46.8002468
  delay: 1m

=head1 DESCRIPTION

Uses L<Astro::Sunrise> to monitor the sunrise and sunset times based
on your location.

A notification will be sent after a state change, and then each hour
before the event.  For example, if the plugin is first run at 6:45pm,
and the sunset is at 9:30pm, then the following messages would be
sent:

  6:45pm - 2h45m until sunset
  7:30pm - 2h until sunset
  8:30pm - 1h until sunset
  9:30pm - sunset
  9:31pm - XhYm until sunrise
  ...

=head1 HINTS

If you find the monitor to be too noisy, the reactor could be used to
suppress some notifications.

=head1 CACHE

The time of the next sunrise or sunset will be cached in the global
cache.  This prevents needing to do the expensive calculation over and
over.

The cache file lives in:

  ~/wubot/cache/SunRise-home.yaml


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
