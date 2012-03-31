package App::Wubot::Reactor::Maildir;
use Moose;

# VERSION

use Maildir::Lite;
use MIME::Entity;
use POSIX qw(strftime);
use Sys::Hostname qw();
use YAML::XS;

use App::Wubot::Logger;

BEGIN {
    # temporarily disable warnings for redefine while we monkey-patch Maildir::Lite
    no warnings 'redefine';

    # Maildir::Lite has a bug where it does not properly handle hostnames with dashes
    *Maildir::Lite::hostname = sub { my $hostname = Sys::Hostname::hostname(); $hostname =~ s|\-||g; return $hostname };

    use warnings 'redefine';
}

sub react {
    my ( $self, $message, $config ) = @_;

    my $mailbox;
    if ( $config->{mailbox} ) {
        $mailbox = $config->{mailbox};
    }
    elsif ( $message->{mailbox} ) {
        $mailbox = $message->{mailbox};
    }
    else {
        $mailbox = lc( $message->{plugin} );
        $mailbox =~ s|^.*\:||;
    }

    my $key = $message->{key} || $message->{plugin};

    my $maildir = Maildir::Lite->new( dir => "$config->{path}/$mailbox" );

    my $directory = join( "/", $config->{path}, $mailbox );
    unless ( $directory ) {
        die "ERROR: path to maildir not specified";
    }
    unless ( -d $directory ) {
        system( "mkdir", $directory );
    }

    my ($fh,$stat0)=$maildir->creat_message();

    die "creat_message failed" if $stat0;

    my $time = $message->{lastupdate} || time;
    my $date = strftime( "%a, %d %b %Y %H:%M:%S %z", localtime( $time ) );

    my $body = $message->{body_text} || $message->{body} || "";
    my $body_text = "FEED:    $key\nSUBJECT: $message->{subject}\n\n$body\n";

    if ( $config->{dump} ) {
        $body = YAML::XS::Dump $message;
    }

    my %message_data = (
        Type        => 'text/plain',
        Date        => $date,
        From        => $message->{mailbox_username} || $message->{username} || $message->{key},
        To          => $message->{to_user}      || 'wubot',
        Subject     => $message->{subject_text} || $message->{subject},
        Data        => $body,
        'X-Key'     => $message->{key},
    );

    if ( $message->{color} ) {
        $message_data{'X-Color'} = $message->{color};
    }

    my $msg = MIME::Entity->build( %message_data );

    if ( $message->{body_text} && $message->{body} ne $message->{body_text} ) {

        $msg->attach( Data => $message->{body},
                      Type => 'text/html',
                  );

    }

    $msg->print($fh);

  TRY:
    do {
        eval {                          # try
            $maildir->deliver_message($fh);
            1;
        } or do {                       # catch
            my $error = $@;

            if ( $error =~ m|already exists| ) {
                redo TRY;
            }

            die "Delivery failed: $error";
        };
    };

    return $message;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Reactor::Maildir - store messages in maildir format

=head1 DESCRIPTION

TODO: More to come...


=head1 SUBROUTINES/METHODS

=over 8

=item react( $message, $config )

The standard reactor plugin react() method.

=back
