package App::Wubot::Plugin::Facebook;
use Moose;

# VERSION

use HTML::TokeParser::Simple;
use HTML::Strip;

use App::Wubot::Logger;
use App::Wubot::Util::WebFetcher;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

has 'fetcher' => ( is  => 'ro',
                   isa => 'App::Wubot::Util::WebFetcher',
                   lazy => 1,
                   default => sub {
                       return App::Wubot::Util::WebFetcher->new();
                   },
               );

has 'htmlstrip' => ( is => 'ro',
                     isa => 'HTML::Strip',
                     lazy => 1,
                     default => sub {
                         return HTML::Strip->new();
                     },
                 );

sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    $self->logger->debug( "Fetching content from: $config->{url}" );

    my $content = $self->fetcher->fetch( $config->{url}, $config );

    $content =~ s|\\u003c|\<|g;
    $content =~ s|\\u200e||g;
    $content =~ s|\\||g;

    my @messages;

    while ( $content =~ m|(<script.*?</script>)|sg ) {

        my $script = $1;

        next unless $script =~ m|pagelet_sub_stream_|;

        $script =~ m|^.*?(<div.*div>)|;

        my $div = $1;

        #print "DIV: $div\n";

        # Parse HTML and pull entires
        my $p = HTML::TokeParser::Simple->new( \$div );

        my $username;

      TOKEN:
        while ( my $token = $p->get_token ) {

            if ( $token->is_tag('div') && $token->as_is =~ m|actorName actorDescription| ) {
                $token = $p->get_token;
                if ( $token->is_tag( 'a' ) || $token->is_tag( 'span' ) ) {
                    $token = $p->get_token;
                }
                $username = $token->as_is;
            } elsif ( $token->as_is =~ m|messageBody| ) {

                my $subject;
                while ( my $token = $p->get_token ) {
                    last if $token->is_end_tag( 'span' );
                    $subject .= " ";
                    next if $token->is_tag( 'br' );
                    next if $token->is_tag( 'a' );
                    next if $token->is_end_tag( 'a' );
                    $subject .= $token->as_is;
                }

                unless ( $subject ) {
                    $self->logger->warn( "WARNING: no subject found!" );
                    next TOKEN;
                }
                $subject = $self->htmlstrip->parse( $subject );

                if ( $username ) {
                    $username = HTML::Entities::decode( $username );
                }

                push @messages, { subject  => $subject,
                                  title    => $subject,
                                  body     => $subject,
                                  username => $username,
                                  link     => $config->{url},
                              };

            } elsif ( $token->is_tag('div') && $token->as_is =~ m|commentContent UIImageBlock_Content| ) {
                $token = $p->get_token;
                if ( $token->is_tag( 'a' ) || $token->is_tag( 'span' ) ) {
                    $token = $p->get_token;
                }
                $username = HTML::Entities::decode( $token->as_is );
            } elsif ( $token->is_tag('span') && $token->as_is =~ m|data-jsid="text"| ) {

                my $subject;
                while ( my $token = $p->get_token ) {
                    last if $token->is_end_tag( 'span' );
                    $subject .= " ";
                    next if $token->is_tag( 'br' );
                    next if $token->is_tag( 'a' );
                    next if $token->is_end_tag( 'a' );
                    $subject .= $token->as_is;
                }

                $subject = $self->htmlstrip->parse( $subject );

                $username = HTML::Entities::decode( $username );

                push @messages, { subject  => $subject,
                                  title    => $subject,
                                  body     => $subject,
                                  username => $username,
                                  link     => $config->{url},
                              };
            }
        }

        my @return;

      MESSAGE:
        for my $message ( @messages ) {

            if ( $self->cache_is_seen( $cache, $message->{subject} ) ) {
                $self->logger->trace( "Already seen: ", $message->{subject} );

                # touch cache time on this subject
                $self->cache_mark_seen( $cache, $message->{subject} );

                next MESSAGE;
            }

            # keep track of this item so we don't alert for it again
            $self->cache_mark_seen( $cache, $message->{subject} );

            push @return, $message;
        }

        $self->cache_expire( $cache );

        my $return = { cache => $cache };

        if ( scalar @return ) {
            $return->{react} = \@return;
        }

        print YAML::Dump \@return;
        print YAML::Dump $return;

        return $return;
    }
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::Facebook - scrape facebook wall

=head1 SYNOPSIS

  ~/wubot/config/plugins/Facebook/drivein.yaml

  ---
  url: http://www.facebook.com/pages/Rodeo-Drive-In-Theatre/115615525131058
  delay: 30m


=head1 DESCRIPTION

This plugin is just a prototype!  It implements a very ugly and
brittle mechanism for scraping a public facebook wall without
requiring logging in to facebook.  It works this week.  It scrapes new
posts and comments.  It can only see the most recent 10 items or so,
so if a page if a lot of comments are posted in a short amount of
time, you will miss some posts.

=head1 WHY?

I do not have a facebook account, but I want to keep up with a few
local businesses that provide updates online through facebook.

  - http://www.facebook.com/pages/Rodeo-Drive-In-Theatre/115615525131058
  - http://www.facebook.com/pages/Colellos-Farm-Stand-Produce/110895085611757
  - http://www.facebook.com/pages/Blackjack-Valley-Farm/170237373016619


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
