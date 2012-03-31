package App::Wubot::Util::Tasks;
use Moose;

# VERSION

use Date::Manip;
use POSIX qw(strftime);

use App::Wubot::Logger;
use App::Wubot::SQLite;

=head1 NAME

App::Wubot::Util::Tasks - utility for dealing with the Emacs Org-Mode files and tasks database

=head1 SYNOPSIS

    use App::Wubot::Util::Tasks;

=head1 DESCRIPTION

Please see L<App::Wubot::Guide::Tasks>.


=cut

has 'sql'    => ( is      => 'ro',
                  isa     => 'App::Wubot::SQLite',
                  lazy    => 1,
                  default => sub {
                      return App::Wubot::SQLite->new( { file => $_[0]->dbfile } );
                  },
              );

has 'dbfile' => ( is      => 'rw',
                  isa     => 'Str',
                  lazy    => 1,
                  default => sub {
                      return join( "/", $ENV{HOME}, "wubot", "sqlite", "tasks.sql" );
                  },
              );

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

my $colors = { deadline => { 2  => '#CC3300',
                             1  => '#BB2200',
                             0  => '#AA1100',
                             -1 => '#990000',
                         },
               due      => { 2  => '#CC9900',
                             1  => '#BB8800',
                             0  => '#AA7700',
                             -1 => '#996600',
                         },
           };

=head1 SUBROUTINES/METHODS

=over 8

=item $obj->get_tasks()

TODO: documentation this method

=cut

sub get_tasks {
    my ( $self, $due, $tag ) = @_;

    my @tasks;

    my $start = time + 15*60;

    my $count;

    my $seen;

    $self->sql->select( { tablename => 'tasks',
                          where     => { 'deadline_utime' => { '<', $start }, status => 'todo' },
                          order     => [ 'priority DESC', 'deadline_utime', 'scheduled_utime', 'lastupdate DESC' ],
                          callback  => sub {
                              my $task = shift;

                              unless ( $task->{tag} ) { $task->{tag} = "null" }
                              if ( $tag ) { return unless $task->{tag} eq $tag }

                              $seen->{$task->{file}}->{$task->{title}} = 1;
                              $task->{subject} = "Past Deadline: $task->{file}.org: $task->{title}\n";

                              $task->{color} = $colors->{deadline}->{ $task->{priority} };

                              $count++;
                              $task->{count} = $count;
                              $task->{urgent} = 1;
                              push @tasks, $task;
                          },
                      } );

    $self->sql->select( { tablename => 'tasks',
                          where     => { 'scheduled_utime' => { '<', $start }, status => 'todo' },
                          order     => [ 'priority DESC', 'scheduled_utime', 'lastupdate DESC' ],
                          callback  => sub {
                              my $task = shift;

                              unless ( $task->{tag} ) { $task->{tag} = "null" }
                              if ( $tag ) { return unless $task->{tag} eq $tag }

                              return if $seen->{$task->{file}}->{$task->{title}};
                              $seen->{$task->{file}}->{$task->{title}} = 1;
                              $task->{subject} = "Overdue: $task->{file}.org: $task->{title}\n";

                              $task->{color} = $colors->{due}->{ $task->{priority} };

                              $count++;
                              $task->{count} = $count;
                              push @tasks, $task;
                          },
                      } );

    my $priority_colors = { 2 => 'yellow', 1 => 'blue', 0 => 'green' };
    unless ( $due ) {
        $self->sql->select( { tablename => 'tasks',
                              where     => { 'priority' => { '>', -1 }, scheduled_utime => undef, deadline_utime => undef, status => 'todo' },
                              order     => [ 'priority DESC', 'lastupdate DESC' ],
                              callback  => sub {
                                  my $task = shift;

                                  unless ( $task->{tag} ) { $task->{tag} = "null" }
                                  if ( $tag ) { return unless $task->{tag} eq $tag }

                                  next if $seen->{$task->{file}}->{$task->{title}};
                                  $seen->{$task->{file}}->{$task->{title}} = 1;
                                  $task->{subject} = "Priority: $task->{file}.org: $task->{title}\n";
                                  $task->{color}   = $priority_colors->{ $task->{priority} };
                                  $count++;
                                  $task->{count} = $count;
                                  push @tasks, $task;
                              },
                          } );
    }

    return @tasks;
}

=item $obj->check_schedule()

TODO: documentation this method

=cut

sub check_schedule {
    my ( $self ) = @_;

    my $now = time;

    my @tasks;
    $self->sql->select( { tablename => 'tasks',
                          where     => { deadline_utime => { '>', $now, '<', $now + 60*15 },
                                         status => 'todo',
                                     },
                          order     => [ 'deadline_utime', 'scheduled_utime', 'priority DESC' ],
                          callback  => sub { my $task = shift;
                                             my $due = strftime( "%l:%M %p", localtime( $task->{deadline_utime} ) );
                                             $task->{subject} = "Deadline: $task->{file}: $task->{title}";
                                             $task->{color}   = 'red';
                                             push @tasks, $task;
                                         },
                      } );

    $self->sql->select( { tablename => 'tasks',
                          where     => { scheduled_utime => { '>', $now, '<', $now + 60*15 },
                                         status    => 'todo',
                                     },
                          order     => [ 'scheduled_utime', 'priority DESC' ],
                          callback  => sub { my $task = shift;
                                             my $due = strftime( "%l:%M %p", localtime( $task->{scheduled_utime} ) );
                                             $task->{subject} = "Scheduled: $task->{file}: $task->{title}";
                                             $task->{color}   = 'yellow';
                                             push @tasks, $task;
                                         },
                      } );

    return @tasks;
}

=item $obj->sync_tasks()

TODO: documentation this method

=cut

sub sync_tasks {
    my ( $self, $file, @tasks ) = @_;

    $self->logger->debug( "Syncing tasks for $file" );

    my %existing_task_ids;

    $self->sql->select( { tablename => 'tasks',
                          where     => { file => $file },
                          callback  => sub { my $task = shift;
                                             $existing_task_ids{ $task->{taskid} } = $task->{id};
                                             $self->logger->trace( "Existing task id: $task->{taskid} => $task->{id}" );
                                         },
                      } );

    my %inserted_task_ids;

  TASK:
    for my $task ( @tasks ) {

        $task->{lastupdate} = time;

        if ( $inserted_task_ids{ $task->{taskid} } ) {
            $self->logger->warn( "Warn: duplicate task id: $task->{taskid}" );
            next TASK;
        }

        $self->sql->insert_or_update( 'tasks',
                                      $task,
                                      { taskid => $task->{taskid} },
                                  );


        $inserted_task_ids{ $task->{taskid} } = 1;
        $self->logger->debug( "updated task id: $task->{taskid}" );


    }

    for my $taskid ( keys %existing_task_ids ) {
        my $id = $existing_task_ids{$taskid};

        unless ( $inserted_task_ids{ $taskid } ) {
            $self->logger->debug( "Removed task: $taskid => $id" );
            $self->sql->delete( 'tasks', { id => $id } );
        }
    }

    return 1;
}

=item $obj->parse_emacs_org_page()

TODO: replace my ugly emacs org mode parsing with L<Org::Parser>


=cut

sub parse_emacs_org_page {
    my ( $self, $orig_filename, $content ) = @_;

    $self->logger->debug( "Parsing $orig_filename" );

    my $filename = $orig_filename;
    $filename =~ s|.org$||;

    my $color = '';

    my @tasks;

  BLOCK:
    for my $block ( split /(?:^|\n)\*+\s/, $content ) {
        $self->logger->trace( "Parsing block: $block" );

        $block =~ s|^\s*\*\s+||mg;

        $block =~ m|^(\w+)|;
        my $name = $1;

        next unless $name;

        if ( $name =~ m|meta|i ) {
            if ( $block =~ m|^\s+\-\scolor\:\s([\w]+)$|m ) {
                $color = "$1";
            }
            next BLOCK;
        }

        unless ( $name eq "TODO" || $name eq "DONE" ) {
            next BLOCK;
        }

        $self->logger->trace( "Parsing $name item" );

        $block =~ s|^\w+\s+||;

        my $task;
        $task->{type} = 'task';

        my $priorities = { C => 0, B => 1, A => 2 };
        if ( $block =~ s|^\[\#(\w)\]\s|| ) {
            $task->{priority} = $priorities->{ $1 };
        } else {
            $task->{priority} = -1;
        }

        if ( $block =~ s|^((?:\d+[smhd])+)\s|| ) {
            $task->{duration} = $1;
        }
        else {
            $task->{duration} = undef;
        }

        $task->{status} = lc( $name );

        $task->{file} = $filename;

        $block =~ s|^(.*)||;
        $task->{title} = $1;

        if ( $task->{title} =~ m|^(.*?)\s+\:(\w+)\:$| ) {
            $task->{title} = $1;
            $task->{tag}   = $2;
        }

        if ( $task->{title} =~ s|\s*\[(\d+.*?)\]\s*$|| ) {
            $task->{progress} = $1;
        }

        $task->{taskid} = join( ".", $task->{file}, $task->{title} );

        $task->{deadline_text}        = undef;
        $task->{deadline_utime}       = undef;
        $task->{deadline_recurrence}  = undef;
        $task->{scheduled_text}       = undef;
        $task->{scheduled_utime}      = undef;
        $task->{scheduled_recurrence} = undef;

        # deadline may be listed before or after schedule.
        # this is an ugly solution that gets it either way
        if ( $block =~ s|^\s+DEADLINE\:\s\<(.*?)(?:\s\.?(\+\d+\w))?\>||m ) {
            $task->{deadline_text}       = $1;
            $task->{deadline_utime}      = UnixDate( ParseDate( $1 ), "%s" ) - 3600;
            $task->{deadline_recurrence} = $2;
        }
        if ( $block =~ s|^\s+SCHEDULED\:\s\<(.*?)(?:\s\.?(\+\d+\w))?\>||m ) {
            $task->{scheduled_text}       = $1;
            $task->{scheduled_utime}      = UnixDate( ParseDate( $1 ), "%s" ) - 3600;
            $task->{scheduled_recurrence} = $2;
        }
        if ( $block =~ s|^\s+DEADLINE\:\s\<(.*?)(?:\s\.?(\+\d+\w))?\>||m ) {
            $task->{deadline_text}       = $1;
            $task->{deadline_utime}      = UnixDate( ParseDate( $1 ), "%s" ) - 3600;
            $task->{deadline_recurrence} = $2;
        }

        $block =~ s|^\s+\- State "DONE"\s+from "TODO"\s+\[.*$||mg;

        $block =~ s|^\s+\n||s;

        $task->{body} = $block;
        $task->{body} =~ s|\s+$||s;

        push @tasks, $task;
    }

    if ( $color ) {
        for my $task ( @tasks ) {
            unless ( $task->{color} ) {
                $task->{color} = $color;
            }
        }
    }

    return @tasks;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=back
