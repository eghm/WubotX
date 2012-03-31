package App::Wubot::Web::TaskbotWeb;
use strict;
use warnings;

# VERSION

use Mojo::Base 'Mojolicious::Controller';

use Data::ICal;
use Data::ICal::Entry::Alarm::Audio;
use Data::ICal::Entry::Alarm::Display;
use Data::ICal::Entry::Event;
use Date::ICal;
use Date::Manip;
use DateTime;
use Digest::MD5 qw( md5_hex );
use File::Path;
use POSIX qw(strftime);
use URI::Escape;
use YAML;

use App::Wubot::Util::Colors;
use App::Wubot::Util::Taskbot;
use App::Wubot::Util::TimeLength;
use App::Wubot::Util::WebUtil;

use App::Wubot::Web::Obj::TaskObj;

my $util    = App::Wubot::Util::WebUtil->new( { type => 'taskbot',
                                                idname => 'taskid',
                                                fields => [ qw( cmd color title link sound body status task_status priority duration category recurrence scheduled ) ],
                                            } );

my $taskbot      = App::Wubot::Util::Taskbot->new();
my $colors       = App::Wubot::Util::Colors->new();
my $timelength   = App::Wubot::Util::TimeLength->new( { space => 1 } );

my $notify_file    = join( "/", $ENV{HOME}, "wubot", "sqlite", "notify.sql" );
my $sqlite_notify  = App::Wubot::SQLite->new( { file => $notify_file } );

my $is_null = "IS NULL";
my $is_not_null = "IS NOT NULL";

sub get_submit_item_postproc {
    my ( $item ) = @_;

    return unless defined $item;

    for my $param ( qw( scheduled ) ) {
        my $value = $item->{$param};
        next unless defined $value;
        if ( ! $value ) {
            $item->{$param} = undef;
        }
        elsif ( $value =~ m|^\d+$| ) {
            $item->{$param} = $value;
        } else {
            $item->{ $param } = UnixDate( ParseDate( $value ), "%s" );
        }
    }
}

sub get_item_postproc {
    my ( $item, $id ) = @_;

    my $body = $taskbot->read_body( $id );
    if ( $body ) {
        $item->{body} = $body;
    }

    return $item;
}

sub cmd {
    my ( $self, $taskid, $cmdlist ) = @_;

    my ( $item ) = $util->get_item( $taskid, \&get_item_postproc );

    for my $cmd ( split /\s*,\s*/, $cmdlist ) {

        if ( $cmd =~ m/(\+|\-)(\d+)(\w)/ ) {
            print "Updating task time to $1 $2 $3\n";
            my $seconds = $timelength->get_seconds( "$1$2$3" );
            $item->{scheduled} = time + $seconds;
        }
        elsif ( $cmd =~ m/(\+|\-)\.(\d+)(\w)/ ) {
            print "Updating task time to relative $1 $2 $3\n";
            my $seconds = $timelength->get_seconds( "$1$2$3" );
            $item->{scheduled} = $item->{scheduled} + $seconds;
        }
        elsif ( $cmd =~ m/s\.(.*)/ ) {
            my $time = $1;
            $item->{scheduled} = UnixDate( ParseDate( $time ), "%s" );
        }
        elsif ( $cmd =~ m/p.(\d+)/ ) {
            $item->{priority} = $1;
        }
        elsif ( $cmd =~ m/d.(\d+\w?)/ ) {
            if ( $1 eq "0" ) {
                $item->{duration} = undef;
            }
            else {
                $item->{duration} = $1;
            }
        }
        elsif ( $cmd =~ m/r.(\d+\w?)/ ) {
            if ( $1 eq "0" ) {
                $item->{recurrence} = undef;
            }
            else {
                $item->{recurrence} = $1;
            }
        }
        elsif ( $cmd eq "todo" ) {
            $item->{status} = "TODO";
        }
        elsif ( $cmd eq "done" ) {
            $item->{status} = "DONE";
        }
        elsif ( $cmd eq "skip" ) {
            $item->{status} = "CANCELLED";
        }
        elsif ( $cmd =~ m/^c.(.*)$/ ) {
            $item->{category} = $1;
        }
        elsif ( $colors->get_color( $cmd ) ne $cmd ) {
            $item->{color} = $cmd;
        }
    }

    $util->update_item( $item, $taskid, \&update_task_preproc, $self );
}

sub update_task_preproc {
    my ( $self, $task_h ) = @_;

    if ( $task_h->{task_status} ) {
        $task_h->{status} = $task_h->{task_status};
    }

    if ( $task_h->{status} ) {
        if ( $task_h->{status} eq "DONE" ) {
            $task_h->{lastdone} = time;

            my ( $task_orig ) = $util->get_item( $task_h->{taskid}, \&get_item_postproc );

            if ( $task_orig->{recurrence} ) {
                $task_h->{status} = "TODO";

                my $next = $timelength->get_seconds( $task_h->{recurrence} );

                if ( $task_orig->{scheduled} ) {
                    $task_h->{scheduled} = $task_orig->{scheduled} + $next;
                }
            }
        } elsif ( $task_h->{status} eq "CANCELLED" ) {
            my ( $task_orig ) = $util->get_item( $task_h->{taskid}, \&get_item_postproc );

            # skipping one occurrence of a recurring task
            if ( $task_orig->{scheduled} && $task_orig->{recurrence} ) {
                $task_h->{status} = "TODO";

                my $next = $timelength->get_seconds( $task_h->{recurrence} );
                $task_h->{scheduled} = $task_orig->{scheduled} + $next;
            }
        }
    }

    if ( $task_h->{body} ) {
        $taskbot->write_body( $task_h->{taskid}, $task_h->{body} );
    }
}

sub item {
    my $self = shift;

    my $taskid = $self->stash( 'taskid' );

    my $got_item = $util->get_submit_item( $self, \&get_submit_item_postproc, $taskid );

    if ( $got_item ) {
        $util->update_item( $got_item, $taskid, \&update_task_preproc, $self );

        if ( $got_item->{cmd} ) {
            $self->cmd( $taskid, $got_item->{cmd} );
        }

        my $redir = $self->param('redir');
        if ( $redir ) {
            $self->redirect_to( "/taskbot/$redir" );
            return;
        }
        $self->redirect_to( "/taskbot/item/$taskid" );
        return;
    }

    my $now = time;

    # get
    my $item_obj = App::Wubot::Web::Obj::TaskObj->new( { redir => "item/$taskid", taskid => $taskid, sql => $taskbot->sql } );
    $self->stash( item => $item_obj );

    $self->render( template => 'taskbot.item' );
}

sub newtask {
    my $self = shift;

    if ( $self->param( 'title' ) ) {
        $self->create_task();
    }

    my $item = { color    => 'blue',
                 title    => 'insert title',
                 body     => 'insert body',
                 status   => 'TODO',
                 priority => 50,
             };

    $item->{display_color} = $colors->get_color( $item->{color} );

    my $item_obj = App::Wubot::Web::Obj::TaskObj->new( { db_hash => $item, sql => $taskbot->sql } );
    $self->stash( item => $item_obj );

    $self->render( template => 'taskbot.item' );
}

sub create_task {
    my $self = shift;

    my $item = $util->get_submit_item( $self, \&get_submit_item_postproc );

    $self->stash( "item" => $item );

    my $task = $taskbot->create_task( $item );

    $self->redirect_to( "/taskbot/item/$task->{taskid}" );
}

sub tasks {
    my ( $self ) = @_;

    my $params = $self->req->params->to_hash;
    for my $param ( sort keys %{ $params } ) {
        next unless $params->{$param};
        next unless $param =~ m|^cmd_([\w\d\-]+)|;
        my $id = $1;

        my $cmd = $params->{$param};

        $self->cmd( $id, $cmd );
    }

    $self->stash( 'headers', [ 'timer', '#', 'cmd', 'status', 'time', 'dur',
                               'title', 'ed', 'link', 'priority', 'rec', 'done',
                               'category', 'updated' ] );

    my $now = time;
    my $start = $now + 15*60;

    my @tasks;

    my $limit = $self->param( 'limit' ) || 200;

    my $query = { tablename => 'taskbot',
                  order     => [ 'scheduled', 'priority DESC', 'id DESC' ],
                  limit     => $limit,
              };

    my $status = $util->check_session( $self, 'task_status' );
    if ( $status ) {
        unless ( $status eq "any" ) {
            $query->{where}->{status} = uc( $status );
        }
        if ( uc($status) eq "DONE" ) {
            $query->{order} = [ 'scheduled DESC', 'priority DESC', 'id DESC' ];
            #print "ORDER: desc\n";
        }
    }
    else {
        $query->{where}->{status}    = "TODO";
    }

    my $category = $util->check_session( $self, 'category' );
    if ( $category ) {
        if ( $category eq "null" ) {
            $query->{where}->{category} = [ undef, "" ];
        }
        elsif ( $category eq "all" ) {
            # no 'where' restricting category
        }
        else {
            $query->{where}->{category} = $category;
        }
    }

    my $is_not_null = "IS NOT NULL";

    my $scheduled = $util->check_session( $self, 'scheduled' );
    if ( $scheduled ) {
        if ( $scheduled eq "false" ) {
            $query->{where}->{scheduled}  = undef;
        }
        elsif ( $scheduled eq "true" ) {
            $query->{where}->{scheduled}  = \$is_not_null;
            unless ( $status && uc( $status ) eq "DONE" ) {
                $query->{order} = [ 'scheduled ASC', 'priority DESC', 'lastupdate DESC' ];
            }
        }
        elsif ( $scheduled eq "future" ) {
            $query->{where}->{scheduled}  = { ">=" => $now };
            unless ( uc( $status ) eq "DONE" ) {
                $query->{order} = [ 'scheduled ASC', 'priority DESC', 'lastupdate DESC' ];
            }
        }
        elsif ( $scheduled eq "past" ) {
            $query->{where}->{scheduled}  = { "<=" => $now };
            unless ( uc( $status ) eq "DONE" ) {
                $query->{order} = [ 'scheduled ASC', 'priority DESC', 'lastupdate DESC' ];
            }
        }
    }

    if ( $self->param( 'order' ) ) {
        $query->{order} = $self->param( 'order' );
    }

    $query->{callback} = sub {
        my $task = shift;
        my $obj  = App::Wubot::Web::Obj::TaskObj->new( { db_hash => $task, sql => $taskbot->sql } );
        push @tasks, $obj;
    };

    $taskbot->sql->select( $query );

    $self->stash( body_data => \@tasks );

    my $where = { status => 'TODO' };
    if ( $util->check_session( $self, 'norecur' ) ) {
        $where = { status => 'TODO', 'recurrence' => [ undef, "" ] };
    }
    my @categories;
    $taskbot->sql->select( { fields => 'category, max(lastupdate) as lastupdate, count(*) as count',
                             tablename => 'taskbot',
                             group => 'category',
                             where => $where,
                             order => 'lastupdate DESC, count DESC',
                             callback => sub {
                                 my $row = shift;
                                 $row->{color} = $timelength->get_age_color( $now - $row->{lastupdate} );
                                 if ( $row->{category} eq "" ) {
                                     $row->{category} = "null";
                                 }
                                 push @categories, $row;
                             },
                         } );
    $self->stash( 'categories', \@categories );

    # my @mailboxes;
    # $sqlite_notify->select( { fields => 'mailbox, lastupdate, count(*) as count',
    #                           tablename => 'notifications',
    #                           group => 'mailbox',
    #                           order => 'lastupdate DESC, count DESC',
    #                           where => { seen => \$is_null },
    #                           callback => sub {
    #                               my $row = shift;
    #                               $row->{color} = $timelength->get_age_color( $now - $row->{lastupdate} );
    #                               push @mailboxes, $row;
    #                           },
    #                       } );
    # $self->stash( 'mailboxes', \@mailboxes );

    $self->render( template => 'taskbot.list' );

}

sub open {
    my $self = shift;

    my $taskid = $self->stash( 'taskid' );

    $taskbot->open( $taskid );

    $self->redirect_to( "/taskbot/item/$taskid" );


}


sub ical {
    my $self = shift;

    my $calendar = Data::ICal->new();

    my $callback = sub {
        my $entry = shift;

        return unless $entry->{duration};

        my @due;

        if ( $entry->{scheduled} ) {
            push @due, $entry->{scheduled};

            if ( $entry->{recurrence} ) {
                my $seconds = $timelength->get_seconds( $entry->{recurrence} );

                for my $count ( 1 .. 3 ) {
                    push @due, $entry->{scheduled} + $seconds;
                }
            }
        }
        else {
            return;
        }

        my $duration = $timelength->get_seconds( $entry->{duration} );

        for my $due ( @due ) {

            my $dt_start = DateTime->from_epoch( epoch => $due );
            my $start    = $dt_start->ymd('') . 'T' . $dt_start->hms('') . 'Z';

            my $dt_end   = DateTime->from_epoch( epoch => $due + $duration );
            my $end      = $dt_end->ymd('') . 'T' . $dt_end->hms('') . 'Z';

            my $id = join "-", 'WUBOT', md5_hex( $entry->{taskid} ), $start;

            my %event_properties = ( summary     => $entry->{title},
                                     dtstart     => $start,
                                     dtend       => $end,
                                     uid         => $id,
                                 );

            if ( $entry->{body} ) {
                $event_properties{description} = $entry->{body};
                utf8::encode( $event_properties{description} );
            }

            my $vevent = Data::ICal::Entry::Event->new();
            $vevent->add_properties( %event_properties );

            if ( $entry->{status} eq "TODO" ) {
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

    my $select = { tablename => 'taskbot',
                   callback  => $callback,
                   where     => { scheduled => { '>', $time } },
                   order     => 'scheduled',
               };

    if ( $self->param( 'task_status' ) ) {
        $select->{where} = { status => $self->param( 'task_status' ) };
    }

    $taskbot->sql->select( $select );

    $self->stash( calendar => $calendar->as_string );

    $self->render( template => 'calendar', format => 'ics', handler => 'epl' );
}

1;

__END__

=head1 NAME

App::Wubot::Web::TaskbotWeb - wubot tasks web interface

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
