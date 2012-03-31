package App::Wubot::Plugin::TaskNotify;
use Moose;

# VERSION

use POSIX qw(strftime);

use App::Wubot::Logger;
use App::Wubot::Util::Taskbot;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

my $taskbot   = App::Wubot::Util::Taskbot->new();

has 'timers' => ( is => 'ro',
                  isa => 'HashRef',
                  lazy => 1,
                  default => sub { return {} },
              );

sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};
    my $config = $inputs->{config};

    my $now = time;

    my $timers;

    for my $task ( $taskbot->check_schedule() ) {

        # use current time for notification, not lastupdate time on record
        delete $task->{lastupdate};

        $task->{subject} = $task->{title};

        $task->{sticky} = 1;
        $task->{urgent} = 1;

        # growl identifier for coalescing
        $task->{growl_id} = $task->{title};

        $task->{link} = "/tasks";

        $timers->{ $task->{taskid} }->{ $task->{scheduled} } = $task;

        if ( $task->{duration} ) {
            my $time = $task->{scheduled} - 10*60;
            $timers->{ $task->{taskid} }->{ $time } = $task;
        }
    }

    # schedule timers for tasks that are not yet scheduled
    for my $taskid ( keys %{ $timers }  ) {
        for my $scheduled ( keys %{ $timers->{ $taskid } } ) {

            if ( $self->timers->{ $taskid } ) {
                next if $self->timers->{ $taskid }->{ $scheduled };
            }

            my $task = $timers->{ $taskid }->{ $scheduled };
            my $seconds = $scheduled - $now;

            $self->timers->{ $taskid }->{ $scheduled }
                = AnyEvent->timer( after => $seconds,
                                   cb    => sub {
                                       $task->{lastupdate} = time;
                                       $self->reactor->( $task, $config );
                                   },
                               );
        }
    }

    # tasks that have timers but have been removed from the db
    for my $taskid ( keys %{ $self->timers } ) {
        for my $scheduled ( keys %{ $self->timers->{ $taskid } } ) {

            next if $timers->{ $taskid }->{ $scheduled };

            delete $self->timers->{ $taskid }->{ $scheduled };
        }
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::TaskNotify - monitor for upcoming scheduled tasks

=head1 SYNOPSIS

  ~/wubot/config/plugins/TaskNotify/org.yaml

  ---
  dbfile: /Users/wu/wubot/sqlite/tasks.sql
  delay: 5m


=head1 DESCRIPTION

The TaskNotify plugin looks in the tasks database for items that are
within 15 minutes of coming due.  For each item, a notification is
sent each time the plugin runs.


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
