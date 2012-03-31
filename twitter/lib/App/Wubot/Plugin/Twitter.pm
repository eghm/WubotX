package App::Wubot::Plugin::Twitter;
use Moose;

# VERSION

use Net::Twitter::Lite;
use Storable;

use App::Wubot::Logger;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

has 'datafile' => ( is => 'rw',
                    isa => 'Str',
                    default => sub {
                        return join( "/", $ENV{HOME}, "wubot", ".twitter-auth.dat" );
                    },
                );

has 'twitter'  => ( is => 'rw',
                    isa => 'Net::Twitter::Lite',
                    default => sub {
                        return Net::Twitter::Lite->new(
                            consumer_key        => 'WdRFWMj2sJhR9YIObmlA',
                            consumer_secret     => 'cGpm2cigZks4C0RGS6G9X2jfm6oXc3UiHpCDVnmDhM',
                        );
                    },
                );

sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    my $access_tokens = eval { retrieve($self->datafile) } || [];

    if ( @$access_tokens ) {
        $self->twitter->access_token($access_tokens->[0]);
        $self->twitter->access_token_secret($access_tokens->[1]);
    }
    else {
        my $auth_url = $self->twitter->get_authorization_url;
        print " Authorize this application at: $auth_url\nThen, enter the PIN# provided to continue: ";

        my $pin = <STDIN>; # wait for input
        chomp $pin;

        # request_access_token stores the tokens in $nt AND returns them
        my @access_tokens = $self->twitter->request_access_token(verifier => $pin);

        # save the access tokens
        store( \@access_tokens, $self->datafile );
    }

    my @react;

  TWEET:
    for my $status ( @{ $self->twitter->friends_timeline({ count => 30 }) } ) {

        if ( $self->cache_is_seen( $cache, $status->{text} ) ) {
            $self->logger->trace( "Already seen: ", $status->{text} );

            # touch cache time on this subject
            $self->cache_mark_seen( $cache, $status->{text} );

            next TWEET;
        }

        $self->cache_mark_seen( $cache, $status->{text} );

        my $subject = $status->{text};
        my $username = lc($status->{user}->{screen_name});

        my $entry = { subject           => $subject,
                      text              => $status->{text},
                      username          => $username,
                      profile_image_url => $status->{user}->{profile_image_url},
                      coalesce          => "Twitter-$username",
                      link              => "http://twitter.com/#!/$username/status/$status->{id}",
                  };

        push @react, $entry;
    }

    $self->cache_expire( $cache );

    return { cache => $cache, react => \@react };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::Twitter - monitor twitter friends timeline

=head1 SYNOPSIS

  ~/wubot/config/plugins/Twitter/me.yaml

  ---
  delay: 5m


=head1 DESCRIPTION

This plugin monitors a twitter account for new tweets in the friends
timeline.  It uses L<Net::Twitter::Lite>.

When a new tweet shows up in your timeline, the message sent will
contain the following fields:

  subject: {tweet text}
  text: {tweet text}
  username: {lowercase twitter user id}
  profile_image_url: {user image url}
  coalesce: Twitter-{username}


=head1 OAuth

To authorize wubot to monitor your twitter feed, start by creating the
twitter config file.  Then run a single check using the wubot-check
script, i.e.

  wubot-check Twitter me

Then follow the instructions to set up your authorization tokens.


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
