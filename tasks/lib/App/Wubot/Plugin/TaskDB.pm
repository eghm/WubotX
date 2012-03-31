package App::Wubot::Plugin::TaskDB;
use Moose;

# VERSION

use DBI;
use POSIX qw(strftime);

use App::Wubot::Logger;
use App::Wubot::Util::Tasks;

my $taskutil   = App::Wubot::Util::Tasks->new();

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};
    my $config = $inputs->{config};

    my $now = time;

    my @tasks = $taskutil->get_tasks();

    return unless scalar @tasks;

    my $task = $tasks[0];

    return unless $task->{deadline} || $task->{scheduled};

    if ( $cache->{lasttask} && $cache->{lasttask} eq $task->{subject} ) {

        # task hasn't changed.  if we've already sent a
        # notification in the last 60 minutes, don't send another.
        if ( $cache->{lastnotify} && time - $cache->{lastnotify} < 3600 ) {
            return;
        }

    }
    else {
        # if this is a new task, set the 'sticky' bit on for the notification
        $task->{sticky} = 1;
    }

    $task->{link} = "/tasks";

    # cache the last task
    $cache->{lasttask}   = $task->{subject};
    $cache->{lastnotify} = time;

    return { react => $task,
             cache => $cache,
         };

}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::TaskDB - monitor the highest priority task in the task db

=head1 DESCRIPTION

Please see L<App::Wubot::Guide::Tasks>.

=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
