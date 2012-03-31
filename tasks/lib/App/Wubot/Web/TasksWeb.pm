package App::Wubot::Web::TasksWeb;
use strict;
use warnings;

# VERSION

use Mojo::Base 'Mojolicious::Controller';

use Data::ICal;
use Data::ICal::Entry::Alarm::Audio;
use Data::ICal::Entry::Alarm::Display;
use Data::ICal::Entry::Event;
use Date::ICal;
use DateTime;
use Digest::MD5 qw( md5_hex );
use POSIX qw(strftime);
use URI::Escape;

use App::Wubot::Util::Tasks;
use App::Wubot::Util::Colors;
use App::Wubot::Util::TimeLength;

my $tasks_file   = join( "/", $ENV{HOME}, "wubot", "sqlite", "tasks.sql" );
my $sqlite_tasks = App::Wubot::SQLite->new( { file => $tasks_file } );
my $taskutil     = App::Wubot::Util::Tasks->new();
my $colors       = App::Wubot::Util::Colors->new();
my $timelength   = App::Wubot::Util::TimeLength->new();

my $dst_flag = ( localtime() )[-1];

sub tasks {
    my $self = shift;

    my $due = $self->param( 'due' );
    if ( $due ) {
        $self->session( due => 1 );
        $self->redirect_to( "/tasks" );
    }
    elsif ( defined $due ) {
        $self->session( due => 0 );
        $self->redirect_to( "/tasks" );
    }
    else {
        $due = $self->session( 'due' );
    }

    my $tag = $self->param( 'tag' );
    if ( $tag ) {
        $self->session( tag => $tag );
        $self->redirect_to( "/tasks" );
    }
    else {
        $tag = $self->session( 'tag' );
    }
    if ( $tag eq "none" ) {
        undef $tag;
    }

    my @tasks = $taskutil->get_tasks( $due, $tag );

    my $now = time;

    for my $task ( @tasks ) {

        $task->{lastupdate_color} = $timelength->get_age_color( $now - $task->{lastupdate} );

        $task->{lastupdate} = strftime( "%Y-%m-%d %H:%M", localtime( $task->{lastupdate} ) );

        if ( $colors->get_color( $task->{color} ) ) {
            $task->{color} = $colors->get_color( $task->{color} );
            $task->{deadline_color} = $task->{color};
            $task->{scheduled_color} = $task->{color};
        }

        for my $type ( qw( deadline scheduled ) ) {
            next unless $task->{"$type\_utime"};

            my $diff = abs( $task->{"$type\_utime"} - $now );
            if ( $diff < 3600 ) {
                $task->{color} = "green";
            } elsif ( $diff < 900 ) {
                $task->{color} = "pink";
            }
            $task->{$type} = $task->{"$type\_text"};

            $task->{"$type\_color"} = $timelength->get_age_color( $now - $task->{"$type\_utime"} );
        }

        if ( $task->{duration} ) {
            $task->{emacs_link} = join( "%20", $task->{duration}, $task->{title} );
        }
        else {
            $task->{emacs_link} = $task->{title};
        }
        $task->{emacs_link} =~ s|\/|__SLASH__|g;
        $task->{emacs_link} = uri_escape( $task->{emacs_link} );
    }

    $self->stash( 'headers', [qw/count lastupdate tag file title priority scheduled deadline/ ] );

    my $tagcolors = { 'null' => 'black', chores => 'blue', work => 'orange', geektank => 'purple' };
    for my $tag ( keys %{ $tagcolors } ) {
        $tagcolors->{$tag} = $colors->get_color( $tagcolors->{$tag} );
    }
    $self->stash( 'tagcolors', $tagcolors );

    $self->stash( 'body_data', \@tasks );

    $self->render( template => 'tasks' );

}

sub ical {
    my $self = shift;

    my $calendar = Data::ICal->new();

    my $callback = sub {
        my $entry = shift;

        return unless $entry->{duration};

        my @due;
        if ( $entry->{deadline_utime} ) {
            push @due, $entry->{deadline_utime};

            if ( $entry->{deadline_recurrence} ) {
                my $seconds = $timelength->get_seconds( $entry->{deadline_recurrence} );

                for my $count ( 1 .. 5 ) {
                    push @due, $entry->{deadline_utime} + $seconds*$count;
                }
            }
        }
        elsif ( $entry->{scheduled_utime} ) {
            push @due, $entry->{scheduled_utime};

            if ( $entry->{scheduled_recurrence} ) {
                my $seconds = $timelength->get_seconds( $entry->{scheduled_recurrence} );

                for my $count ( 1 .. 3 ) {
                    push @due, $entry->{scheduled_utime} + $seconds;
                }
            }
        }
        else {
            return;
        }

        my $duration = $timelength->get_seconds( $entry->{duration} );

        for my $due ( @due ) {

            unless ( $dst_flag ) { $due += 3600 }

            my $dt_start = DateTime->from_epoch( epoch => $due );
            my $start    = $dt_start->ymd('') . 'T' . $dt_start->hms('') . 'Z';

            my $dt_end   = DateTime->from_epoch( epoch => $due + $duration );
            my $end      = $dt_end->ymd('') . 'T' . $dt_end->hms('') . 'Z';

            my $id = join "-", 'WUBOT', md5_hex( $entry->{taskid} ), $start;

            my %event_properties = ( summary     => $entry->{taskid},
                                     dtstart     => $start,
                                     dtend       => $end,
                                     uid         => $id,
                                 );

            $event_properties{description} = $entry->{body};
            utf8::encode( $event_properties{description} );

            my $vevent = Data::ICal::Entry::Event->new();
            $vevent->add_properties( %event_properties );

            if ( $entry->{status} eq "todo" ) {
                for my $alarm ( 10 ) {

                    my $alarm_time = $due - 60*$alarm;

                    my $valarm_sound = Data::ICal::Entry::Alarm::Audio->new();
                    $valarm_sound->add_properties(
                        trigger   => [ Date::ICal->new( epoch => $alarm_time )->ical, { value => 'DATE-TIME' } ],
                    );
                    $vevent->add_entry($valarm_sound);
                }
            }

            $calendar->add_entry($vevent);
        }
    };

    # last 30 days worth of data
    my $time = time - 60*60*24*30;

    my $select = { tablename => 'tasks',
                   callback  => $callback,
                   where     => [ { scheduled_utime => { '>', $time } }, { deadline_utime => { '>', $time } } ],
                   order     => 'deadline_utime, scheduled_utime',
               };

    if ( $self->param( 'status' ) ) {
        $select->{where} = { status => $self->param( 'status' ) };
    }

    $sqlite_tasks->select( $select );

    $self->stash( calendar => $calendar->as_string );

    $self->render( template => 'calendar', format => 'ics', handler => 'epl' );
}

sub open {
    my $self = shift;

    my $filename = $self->stash( 'file' );
    $filename =~ tr/A-Za-z0-9\.\-\_//cd;
    print "FILENAME: $filename\n";

    my $link = uri_unescape( $self->stash( 'link' ) );
    $link =~ s|[\'\"]|.|g;
    $link =~ s|__SLASH__|/|g;
    $link = "file:/Users/wu/org/$filename\:\:$link";

    my $command;
    if ( $self->param('done') ) {
        my $emacs_foo = qq{ (progn (org-open-link-from-string "[[$link]]" )(pop-to-buffer "$filename")(delete-other-windows)(org-todo)(save-buffer)(raise-frame)) };
        $command = qq(emacsclient --socket-name /tmp/emacs501/server -e '$emacs_foo' &);
    }
    elsif ( $self->param('yesterday') ) {
        my $emacs_foo = qq{ (progn (org-open-link-from-string "[[$link]]" )(pop-to-buffer "$filename")(delete-other-windows)(org-todo-yesterday)(save-buffer)(raise-frame)) };
        $command = qq(emacsclient --socket-name /tmp/emacs501/server -e '$emacs_foo' &);
    }
    else {
        my $emacs_foo = qq{ (progn (org-open-link-from-string "[[$link]]" )(pop-to-buffer "$filename")(delete-other-windows)(raise-frame)) };
        $command = qq(emacsclient --socket-name /tmp/emacs501/server -e '$emacs_foo' &);
    }

    print "EMACS: $command\n";
    system( $command );

    # switch to x11 emacs
    system( qq{osascript -e 'tell app "X11" to activate'} );

    $self->redirect_to( "/tasks?due=1" );
}

1;

__END__

=head1 NAME

App::Wubot::Web::TasksWeb - wubot tasks web interface

=head1 CONFIGURATION

   ~/wubot/config/webui.yaml

    ---
    plugins:
      tasks:
        '/tasks': tasks
        '/ical': ical
        '/open/org/(.file)/(.link)': open


=head1 DESCRIPTION

The wubot web interface is still under construction.  There will be
more information here in the future.

TODO: finish docs

=head1 SUBROUTINES/METHODS

=over 8

=item tasks

Display the tasks web ui.

=item ical

Export tasks as an ical.

=item open

Open the specified file to a specific link in emacs using emacsclient.

=back
