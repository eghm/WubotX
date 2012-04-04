package App::Wubot::Plugin::SafariBookmarks;
use Moose;

# VERSION

use LWP::Simple;
use XML::Simple;

use App::Wubot::Logger;

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

my $file = join( "/", $ENV{HOME}, "Library", "Safari", "Bookmarks.plist" );

my $xml = new XML::Simple;

sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    unless ( -r $file ) {
        $self->logger->logdie( "Error: bookmarks file not found: $file" );
    }

    my $tmpfile = "/tmp/bookmarks.plist";

    if ( -r $tmpfile ) {
        unlink $tmpfile;
    }

    $self->logger->debug( "Copying $file to $tmpfile" );
    system( "cp", $file, $tmpfile );

    $self->logger->debug( "Converting to xml..." );
    system( "plutil", "-convert", "xml1", $tmpfile );


    my $data = $xml->XMLin( $tmpfile );

    my $new = {};

    $self->_parse_data( $data, $cache, $new );

    my @react;

    for my $url ( keys %{ $new } ) {
        my $react = { link => $url };

        my $content = get( $url );

        if ( $content =~ m|<title>(.*)</title>|is ) {
            $react->{subject} = $1;
            $react->{subject} =~ s|^[\'\s]+||;
            $react->{subject} =~ s|[\'\s]+$||;
        }
        else {
            $react->{subject} = $url;
        }

        push @react, $react;
    }

    $self->cache_expire( $cache );

    return { cache => $cache, react => \@react };
}

sub _parse_data {
    my ( $self, $data, $cache, $new ) = @_;

    if ( ref $data eq "ARRAY" ) {
        for my $subdata ( @{ $data } ) {
            $self->_parse_data( $subdata, $cache, $new );
        }
        return;
    }

    if ( $data->{dict} ) {
        $self->_parse_data( $data->{dict}, $cache, $new );
    }

    if ( $data->{array} ) {
        $self->_parse_data( $data->{array}, $cache, $new );
    }

    if ( $data->{string} ) {
        if ( ref $data->{string} eq "ARRAY" ) {
            for my $string ( @{ $data->{string} } ) {
                if ( $string =~ m|http\:\/\/| ) {

                    # if we've already seen this item, move along
                    if ( $self->cache_is_seen( $cache, $string ) ) {
                        $self->logger->trace( "Already seen: ", $string );

                        # touch cache time on this subject
                        $self->cache_mark_seen( $cache, $string );

                        next;
                    }

                    $new->{ $string } = 1;

                    # mark this item as new
                    $self->cache_mark_seen( $cache, $string );

                }
            }
        }
    }

}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::SafariBookmarks - monitor for new safari bookmarks

=head1 DESCRIPTION

This plugin is just a prototype!  Lots more to do here.

Currently this plugin copies the safari bookmarks file:

  ~/Library/Safari/Bookmarks.plist

The file is copied to:

  /tmp/bookmarks.plist

Then the 'plutil' utility is used to convert the plist to XML:

  plutil -convert xml1 /tmp/bookmarks.plist

The file is then read in to a data structure using XML::Simple.  The
data structure is walked recursively, and all unique URLs in the data
structure are returned.  Only the URLs are matched; no further parsing
of the file has been implemented yet.  An attempt is made to fetch the
content of the URL using LWP::Simple in order to grab the page title.
If the attempt succeeds, the resulting message will have the title set
in the 'subject' field, e.g.:

  subject: Slashdot: News for nerds, stuff that matters
  link: http://www.slashdot.org/

If the attempt to fetch the title fails, the subject will simply be
set to the URL:

  subject: http://www.slashdot.org/
  link: http://www.slashdot.org/

This plugin uses the wubot caching mechanism, so that messages are
only sent when a new URL is found in your bookmarks.

This does also find items added to the reading list in OS X Lion.


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
