package App::Wubot::Plugin::Outlook;
use Moose;

# VERSION

use Date::Manip;
use Encode;
use HTML::TableExtract;
use LWP::UserAgent;

use App::Wubot::Logger;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};
    my $config = $inputs->{config};

    my @react;

    my $content = $self->_get_content( $config->{url}, $config );

    unless ( $content ) {
        $self->logger->logdie( "Critical: outlook: No content retrieved!" );
    }

    my $count = scalar $self->_get_msgids( $content );

    my $message = { count => $count, coalesce => $self->key };

    if ( $count ) {
        $message->{subject} = "$count messages in your inbox";
    }

    push @react, $message;

    return { react => \@react };
}

sub _get_msgids {
    my ( $self, $content ) = @_;

    my @msgids;

    $content =~ s{name="chkmsg" value="([^"]+)"}{push @msgids, $1}eg;

    my @return;

    for my $msgid ( @msgids ) {
        $msgid =~ s|\/|%2f|g;
        $msgid =~ s|\+|%2b|g;
        push @return, $msgid;
    }

    return @return;
}

sub _get_content {
    my ( $self, $url, $config ) = @_;

    my $ua = new LWP::UserAgent;
    $ua->timeout(15);

    if ( $config->{proxy} ) {
        $ua->proxy(['http'],  $config->{proxy} ); # set proxy
        $ua->proxy(['https'], $config->{proxy} ); # set proxy
    }

    $ua->agent("Mozilla/6.0");  # Or something equally mysterious

    my $req = new HTTP::Request GET => $url;
    $req->authorization_basic( $config->{user}, $config->{pass} );

    my $res = $ua->request($req);

    unless ($res->is_success) {
        $self->logger->warn( "Failure checking outlook web: " . $res->status_line );
        return;
    }

    my $content= $res->content;

    return $content;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::Outlook - monitor number of emails in the inbox using Outlook Web

=head1 SYNOPSIS

  ~/wubot/config/plugins/Outlook/work.yaml

  ---
  url: https://webmail.something.net/owa/
  user: username
  pass: mypass
  delay: 5m

=head1 DESCRIPTION

This plugin is just a prototype!  It implements a very ugly and
brittle mechanism for scraping the outlook web access HTML page for
new items in the inbox.  It only returns the total number of emails in
your inbox, up to the maximum number of emails configured to be shown
per page.  If you inbox contains any email, a message will be sent
containing the fields:

  count: {number}

This is probably only useful if you practice inbox zero.

  - http://inboxzero.com/

If anyone has a better way to parse information from outlook web,
please let me know!


=head1 HINTS

You could easily add a rule to suppress the message until your email
box gets beyond a certain number of emails.

  react:

    - name: minimum count notification
      condition: contains count AND count < 5
      last_rule: 1



=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
