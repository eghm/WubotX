package App::Wubot::Plugin::FirefoxBookmarks;
use Moose;

# VERSION

use YAML::XS;

use App::Wubot::Logger;
use App::Wubot::SQLite;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';


sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    my $db   = $config->{database};

    unless ( $db ) {
        $self->logger->logdie( "ERROR: no database found in config" );
    }

    unless ( -r $db ) {
        $self->logger->logdie( "ERROR: database does not exist: $db" );
    }

    my $sqlite =  App::Wubot::SQLite->new( { file => $db } );

    my @react;

    $sqlite->select( { tablename => 'moz_bookmarks LEFT JOIN moz_places ON moz_bookmarks.fk = moz_places.id',
                       schema    => {},
                       callback  => sub {
                           my $entry = shift;

                           return unless $entry->{url};
                           return unless $entry->{url} =~ m|^http|g;

                           # if we've already seen this item, move along
                           if ( $self->cache_is_seen( $cache, $entry->{url} ) ) {
                               $self->logger->trace( "Already seen: ", $entry->{url} );

                               # touch cache time on this subject
                               $self->cache_mark_seen( $cache, $entry->{url} );

                               return;
                           }

                           # keep track of this item so we don't fetch it again
                           $self->cache_mark_seen( $cache, $entry->{url} );

                           my $react;

                           $react->{link}    = $entry->{url};
                           $react->{subject} = $entry->{title};

                           push @react, $react;
                       },
                   } );

    $self->cache_expire( $cache );

    return { cache => $cache, react => \@react };
}


__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::FirefoxBookmarks - monitor for new firefox bookmarks

=head1 DESCRIPTION

This plugin connects to the firefox 'places' sqlite database and
retrieves the bookmarks.  It caches bookmarks that have previously
been seen, so only new bookmarks trigger event messages.

This plugin uses the wubot caching mechanism, so that messages are
only sent when a new URL is found in your bookmarks.

=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
