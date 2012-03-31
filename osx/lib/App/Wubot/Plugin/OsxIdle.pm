package App::Wubot::Plugin::OsxIdle;
use Moose;

# VERSION

use App::Wubot::Logger;
use App::Wubot::Util::TimeLength;

has 'timelength' => ( is => 'ro',
                      isa => 'App::Wubot::Util::TimeLength',
                      lazy => 1,
                      default => sub {
                          return App::Wubot::Util::TimeLength->new();
                      },
                  );

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );


with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

my $command = "ioreg -c IOHIDSystem";

my $last_notification;

sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    my $idle_sec;

    for my $line ( split /\n/, `$command` ) {

        # we're looking for the first line containing Idle
        next unless $line =~ m|Idle|;

        # capture idle time from end of line
        $line =~ m|(\d+)$|;
        $idle_sec = $1;

        # divide to get seconds
        $idle_sec /= 1000000000;

        $idle_sec = int( $idle_sec );

        $self->logger->debug( "IDLE SEC: $idle_sec => $line" );

        last;
    }

    my $results;

    my $stats;
    ( $stats, $cache ) = $self->_calculate_idle_stats( time, $idle_sec, $config, $cache );

    # add all stats to both the cache and results
    for my $stat ( keys %{ $stats } ) {

        if ( defined $stats->{$stat} ) {
            $results->{$stat} = $stats->{$stat};
            $cache->{$stat}   = $stats->{$stat};
        }
        else {
            # value is 'undef', remove it from the cache data
            delete $cache->{$stat};
        }
    }

    $results->{coalesce} = "OsxIdle";

    $self->logger->debug( "idle_min:$stats->{idle_min} idle_state:$stats->{idle_state} active_min:$stats->{active_min}" );

    return { cache => $cache, react => $results };
}

 sub _calculate_idle_stats {
     my ( $self, $now, $seconds, $config, $cache ) = @_;

     my $stats;
     $stats->{idle_sec} = $seconds;
     $stats->{idle_min} = int( $seconds / 60 );

     my $idle_threshold = $config->{idle_threshold} || 10;

     if ( $cache->{lastupdate} ) {
         my $age = $now - $cache->{lastupdate};
         if ( $age >= $idle_threshold*60 ) {
             $self->logger->debug( "OsxIdle: cache expired" );
             $stats->{cache_expired} = 1;
             delete $cache->{last_idle_state};
             delete $cache->{idle_since};
             delete $cache->{active_since};
         }
         else {
             $stats->{cache_expired} = undef;
             $stats->{last_age_secs} = $age;
         }
     }
     else {
         $stats->{cache_expired} = undef;
     }

     $stats->{lastupdate} = $now;

     if ( exists $cache->{idle_state} ) {
         $stats->{last_idle_state} = $cache->{idle_state} || 0;
     }

     $stats->{last_idle_min} = $cache->{idle_min};
     $stats->{idle_state} = $stats->{idle_min} >= $idle_threshold ? 1 : 0;

     if ( exists $stats->{last_idle_state} && $stats->{last_idle_state} != $stats->{idle_state} ) {
         $stats->{idle_state_change} = 1;
     }
     else {
         $stats->{idle_state_change} = undef;
     }

     if ( $stats->{idle_state} ) {
         # user is currently idle
         $stats->{active_since} = undef;

         $stats->{last_active_min} = $cache->{active_min} || 0;
         $stats->{active_min} = 0;


         if ( $cache->{idle_since} ) {
             $stats->{idle_since} = $cache->{idle_since};
         }
         else {
             $stats->{idle_since} = $now - $stats->{idle_sec};
         }
     }
     else {
         # user is currently active

         $stats->{idle_since} = undef;

         if ( $cache->{active_since} ) {
             $stats->{active_since} = $cache->{active_since};
             $stats->{active_min} = int( ( $now - $cache->{active_since} ) / 60 ) - $stats->{idle_min};
         }
         else {
             $stats->{active_since} = $now;
             $stats->{active_min} = 0;
         }

     }

     if ( $stats->{idle_state_change} ) {
         if ( $stats->{idle_state} ) {
             my $length = $self->timelength->get_human_readable( $stats->{last_active_min} . "m" );
             $stats->{subject} = "idle after being active for $length";
         }
         else {
             my $length = $self->timelength->get_human_readable( $stats->{last_idle_min} . "m" );
             $stats->{subject} =  "active after being idle for $length";
         }
     }
     elsif ( $stats->{idle_state} ) {
         if ( $stats->{idle_min} % 60 == 0 && $stats->{idle_min} > 0 ) {
             my $length = $self->timelength->get_human_readable( $stats->{idle_min} . "m" );
             $stats->{subject} = "idle for $length";
         }
     }
     else {
         if ( $stats->{active_min} % 60 == 0 && $stats->{active_min} > 0 ) {
             my $length = $self->timelength->get_human_readable( $stats->{active_min} . "m" );
             $stats->{subject} = "active for $length";
         }
     }

     if ( $stats->{subject} ) {
         $self->logger->debug( $stats->{subject} );
     }

     if ( $stats->{subject} && $last_notification && $stats->{subject} eq $last_notification ) {
         delete $stats->{subject};
     }
     $last_notification = $stats->{subject};

     return ( $stats, $cache );
}

__PACKAGE__->meta->make_immutable;

1;

__END__


=head1 NAME

App::Wubot::Plugin::OsxIdle - monitor idle time on OS X


=head1 SYNOPSIS

  ~/wubot/config/plugins/OsxIdle/myhost.yaml

  ---
  delay: 1m


=head1 DESCRIPTION

Monitor user idle time on OS X.  Runs the command:

  ioreg -c IOHIDSystem

in order to determine the amount of time since the last input on any
keyboard or mouse.

Any time there has been more than 10 minutes of no activity, you will
be considered idle.

Each time your state changes between idle and active, a message will
be sent informing you the amount of time you spent in the previous
state.

Also each hour you are idle or active, a message will be sent telling
you the amount of time you have spent in that state.  This can be
useful to remind you to stretch or take a break after a certain amount
of time being active.

This plugin is designed to be run every 60 seconds.

If anyone is aware of a command that can be run for other operating
systems to provide idle time, please let me know.

=head1 GRAPHING

If you want to build graphs of the amount of time you are spending
active/idle, then you could use the following rule in the reactor:

  - name: OS X Idle
    condition: key matches ^OsxIdle
    rules:
      - name: add active_min and idle_min to rrd
        plugin: RRD
        last_rule: 1
        config:
          base_dir: /usr/home/wu/wubot/rrd
          fields:
            idle_min: GAUGE
            active_min: GAUGE
          period:
            - day
            - week
          graph_options:
            lower_limit: 0
            upper_limit: 60
            rigid: ""
            sources:
              - active_min
              - idle_min
            source_colors:
              - FF9933
              - 9933FF
            source_drawtypes:
              - AREA
              - AREA
            right-axis: 1:0
            width: 375


See some example graphs here:

  - http://www.geekfarm.org/wu/wubot/OsxIdle-navi-daily.png
  - http://www.geekfarm.org/wu/wubot/OsxIdle-navi-weekly.png

=head1 SEE ALSO

If you use this plugin, you may also be interested in
L<App::Wubot::Plugin::WorkHours>.


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
