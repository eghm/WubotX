package App::Wubot::Reactor::IRC;
use Moose;

# VERSION

use AnyEvent;
use AnyEvent::IRC::Client;
use POSIX qw(strftime);

use App::Wubot::Logger;

has 'logger'      => ( is => 'ro',
                       isa => 'Log::Log4perl::Logger',
                       lazy => 1,
                       default => sub {
                           return Log::Log4perl::get_logger( __PACKAGE__ );
                       },
                   );

has 'con'         => ( is      => 'rw',
                       isa     => 'AnyEvent::IRC::Client',
                       lazy    => 1,
                       default => sub { return AnyEvent::IRC::Client->new() },
                   );

has 'initialized' => ( is      => 'rw',
                       isa     => 'Bool',
                       default => 0,
                   );

has 'connected'   => ( is      => 'rw',
                       isa     => 'Bool',
                       default => 0,
                   );

my $bold      = "\002";
my $escape    = "\003";
my $reset     = "\017";
my $invert    = "\026";
my $underline = "\037";

my %color = ( white      => 0,
              black      => 1,
              blue       => 12,
              green      => 3,
              lightred   => 4,
              red        => 5,
              magenta    => 6,
              orange     => 7,
              yellow     => 8,
              lightgreen => 9,
              cyan       => 10,
              lightcyan  => 11,
              lightblue  => 12,
              pink       => 13,
              grey       => 14,
              lightgrey  => 15,
);

sub react {
    my ( $self, $message, $config ) = @_;

    return $message unless $message->{subject};
    return $message if $message->{quiet};
    return $message if $message->{irc_quiet};

    unless ( $self->initialized ) {
        $self->_init( $config );
    }

    # code_smell: queue messages and send when connected
    return $message unless $self->connected;

    my $subject = $message->{subject_text} || $message->{subject};

    my $date = strftime( "%H:%M", localtime( $message->{lastupdate} ) );
    my $key = $message->{key} || "?";

    if ( $message->{username} ) {
        $subject = "$message->{username}: $subject";
    }

    $subject = "[$date $key] $subject";

    # colorize messages
    if ( $message->{color} && exists $color{ $message->{color} } ) {
        my $msg_color = $color{ $message->{color } };
        $subject = "$escape$msg_color$subject$escape$reset";
    }

    utf8::encode( $subject );

    $self->con->send_srv( PRIVMSG => $config->{channel}, $subject );

    return $message;
}



sub _init {
    my ( $self, $config ) = @_;

    $self->con->reg_cb( registered  => sub { $self->logger->info( "reactor connected to IRC: $config->{server}:$config->{port}" );
                                             $self->logger->info( "joining: $config->{channel}" );
                                             $self->con->send_srv("JOIN", $config->{channel} );
                                             $self->connected( 1 );
                                             $self->con->enable_ping( 60,
                                                                      sub {
                                                                          $self->logger->error( "ping: no response received" );
                                                                          $self->con->disconnect;
                                                                          $self->con( AnyEvent::IRC::Client->new() );
                                                                          $self->initialized( 0 );
                                                                          $self->connected( 0 );

                                                                      } );
                                         }
                    );

    $self->con->reg_cb( disconnect  => sub { $self->logger->info( "disconnected" );
                                             $self->initialized( undef );
                                             $self->connected( 0 );
                                         }
                    );

    $self->con->connect ( $config->{server},
                          $config->{port},
                          { nick     => $config->{nick},
                            password => $config->{password},
                        }
                      );

    $self->initialized( 1 );

    $self->logger->info( "Initialized connection $config->{server}:$config->{port} => $config->{nick}" );
}

sub _close {
    my ( $self ) = @_;
    $self->con->disconnect;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Reactor::IRC - public and private IRC notifications


=head1 DESCRIPTION

For more info, please see the irc.txt document in the docs directory.

=head1 SUBROUTINES/METHODS

=over 8

=item react( $message, $config )

The standard reactor plugin react() method.

=back

