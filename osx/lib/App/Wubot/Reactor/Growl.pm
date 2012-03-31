package App::Wubot::Reactor::Growl;
use Moose;

# VERSION

use POSIX qw(strftime);
use Sys::Hostname qw();

my $growl_enabled = 1;
eval "use Growl::Tiny";  ## no critic (ProhibitStringyEval)
if ( $@ ) { $growl_enabled = 0 }

use App::Wubot::Logger;

my $hostname = Sys::Hostname::hostname();
$hostname =~ s|\..*$||;

sub react {
    my ( $self, $message, $config ) = @_;

    return $message unless $growl_enabled;
    return $message if $message->{quiet};
    return $message if $message->{quiet_growl};

    my $subject = $message->{subject_text} || $message->{subject};
    return $message unless $subject;

    my $sticky = $message->{sticky} ? 1 : 0;

    my $priority = $message->{growl_priority} || $message->{priority};

    my $notification = { sticky   => $sticky,
                         priority => $priority,
                         subject  => $subject,
                         host     => 'localhost',
                     };

    my $date;

    if ( $message->{lastupdate} ) {
        if ( time - $message->{lastupdate} > 86400 ) {
            $date = strftime( "%d/%H:%M", localtime( $message->{lastupdate} ) );
        }
        else {
            $date = strftime( "%H:%M", localtime( $message->{lastupdate} ) );
        }
    }
    else {
        $date = strftime( "%H:%M", localtime( time ) );
    }

    my $title;
    if ( $message->{growl_title} ) {
        $title = $message->{growl_title};
    }
    else {
        if ( $message->{username} ) {
            $title = "$message->{username} ";
        }
        if ( $message->{key} ) {
            $title .= "[$message->{key}]";
        }
        $title .= " $date";
    }
    $notification->{title} = $title;

    if ( $message->{icon} ) {
        $notification->{image} = $message->{icon};
    }

    if ( $message->{growl_id} ) {
        $notification->{identifier} = $message->{growl_id};
    }
    elsif ( $message->{coalesce} ) {
        $notification->{identifier} = $message->{coalesce};
    }
    else {
        my $id = $message->{key} || $subject;

        $notification->{identifier} = join( ":", $id, $sticky );;
    }

    $notification->{results} = Growl::Tiny::notify( $notification );

    $message->{growl}->{$hostname} = $notification;

    return $message;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Reactor::Growl - display a growl notification on OS X using Growl::Tiny

=head1 SYNOPSIS

      - name: growl notify
        plugin: Growl


=head1 DESCRIPTION

For more information, please see L<App::Wubot::Guide::Notifications>.

=head1 SUBROUTINES/METHODS

=over 8

=item react( $message, $config )

The standard reactor plugin react() method.

=back
