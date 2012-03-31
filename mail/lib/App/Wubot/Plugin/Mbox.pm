package App::Wubot::Plugin::Mbox;
use Moose;

# VERSION

use Mail::MboxParser;

use App::Wubot::Logger;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    my $parseropts = {
        enable_cache    => 0,
        enable_grep     => 1,
        cache_file_name => 'mail/cache-file',
    };

    my $key = $self->key;

    my $mb = Mail::MboxParser->new( $config->{path},
                                    decode     => 'ALL',
                                    parseropts => $parseropts
                                );

    my @react;

    my $now = time;

    my $new_count = 0;
  MESSAGE:
    while (my $msg = $mb->next_message) {

        next unless $msg->header->{subject};
        next if $msg->header->{subject} eq "DON'T DELETE THIS MESSAGE -- FOLDER INTERNAL DATA";

        my $id = $msg->header->{'message-id'};

        # ignore messages we've already seen
        if ( $self->cache_is_seen( $cache, $id ) ) {

            # update the last seen time
            $self->cache_mark_seen( $cache, $id );

            next MESSAGE;
        }

        # cache this new id
        $self->cache_mark_seen( $cache, $id );

        $new_count++;

        # new message
        push @react, { subject  => $msg->header->{subject},
                       username => $msg->header->{from},
                       cc       => $msg->header->{cc},
                       to_user  => $msg->header->{to},
                       date     => $msg->header->{date},
                   };

    }
    if ( $new_count ) {
        $self->logger->info( "Found new emails: $key: $new_count" );
    }

    # expire old subjects from the cache
    $self->cache_expire( $cache );

    return { cache => $cache, react => \@react };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::Mbox - monitor an Mbox file


=head1 SYNOPSIS

   ~/wubot/config/plugins/Mbox/inbox.yaml

  ---
  delay: 60
  path: /var/mail/wu


=head1 DESCRIPTION

This monitor uses L<Mail::MboxParser> to monitor for new emails in an
mbox.  Each time a new email arrives in the mbox, a message will be
sent containing:

  subject: the email subject
  username: the email 'from' field
  cc: the email 'cc' field
  to_user: the email 'to' field
  date: the email 'date' field

=head1 CACHE

The Mbox monitor uses the global cache mechanism, so each time the
check runs, it will update a file such as:

  ~/wubot/cache/Mbox-inbox.yaml

The monitor caches all message IDs in the feed.  When a new
(previously unseen) message id shows up on the feed, the message will
be sent, and the cache will be updated.  Removing the cache file will
cause all items in the feed to be sent again.


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
