package App::Wubot::Reactor::Command;
use Moose;

# VERSION

use FileHandle;
use File::Path;
use POSIX qw(strftime setsid :sys_wait_h);
use Term::ANSIColor;
use Text::Template;
use YAML::XS;

use App::Wubot::Logger;
use App::Wubot::SQLite;

has 'logger'   => ( is       => 'ro',
                    isa      => 'Log::Log4perl::Logger',
                    lazy     => 1,
                    default  => sub {
                        return Log::Log4perl::get_logger( __PACKAGE__ );
                    },
                );

has 'logdir'   => ( is       => 'ro',
                    isa      => 'Str',
                    lazy     => 1,
                    default  => sub {
                        my $self = shift;
                        return join( "/", $ENV{HOME}, "wubot", "commands" );
                    },
                );

has 'queuedb'   => ( is       => 'ro',
                     isa      => 'Str',
                     lazy     => 1,
                     default  => sub {
                         my $self = shift;
                         return join( "/", $ENV{HOME}, "wubot", "sqlite", "command.sql" );
                     },
                 );

has 'sqlite'    => ( is       => 'ro',
                     isa      => 'App::Wubot::SQLite',
                     lazy     => 1,
                     default  => sub {
                         my $self = shift;
                         $self->logger->warn( "Command: connecting to sqlite db: ", $self->queuedb );
                         return App::Wubot::SQLite->new( { file => $self->queuedb } );
                     },
               );

my $is_null = "IS NULL";
my $is_not_null = "IS NOT NULL";

sub react {
    my ( $self, $message, $config ) = @_;

    my $output = "";

    my $command;
    if ( $config->{command} ) {
        $self->logger->debug( "Running configured command: $config->{command}" );
        $command = $config->{command};
    }
    elsif ( $config->{command_field} ) {
        $command = $message->{ $config->{command_field} };

        unless ( $command ) {
            $self->logger->error( "ERROR: command_field $config->{command_field} is blank, no command executed" );
            return $message;
        }

        $self->logger->debug( "Running command field: $config->{command_field}: $command " );
    }
    elsif ( $config->{command_array} ) {
        $command = join( " ", @{ $config->{command_array} } );
    }
    else {
        $self->logger->error( "Command reactor error: no command or command_field specified in config" );
        return $message;
    }

    my $template = Text::Template->new(TYPE => 'STRING', SOURCE => $command );
    $command = $template->fill_in( HASH => $message );
    $self->logger->debug( "COMMAND: $command\n" );

    $command =~ s|\\|\\\\|g;

    # wtf?
    #$command =~ s|\>|\\>|g;

    if ( $config->{command_noresults} ) {
        $message->{command_noresults} = 1;
    }

    if ( $config->{fork} ) {
        return $self->_enqueue( $command, $message, $config );
    }

    $output = `$command 2>&1`;
    chomp $output;

    my $results = $?;

    # check exit status
    my $status = 0;
    my $signal = 0;

    unless ( $? eq 0 ) {
        $status = $? >> 8;
        $signal = $? & 127;
        $self->logger->error( "Error running command: $command\n\tstatus=$status\n\tsignal=$signal\nOUTPUT:\n$output" );
    }


    if ( $config->{output_field} ) {
        $message->{ $config->{output_field} } = $output;
    }
    else {
        $message->{command_output} = $output;
    }

    $message->{command_signal} = $signal;
    $message->{command_status} = $status;

    return $message;
}

sub monitor {
    my ( $self ) = @_;

    # clean up any child processes that have exited
    $self->logger->trace( "Command: killing zombies" );
    waitpid(-1, WNOHANG);

    my @messages;

    my $directory = $self->logdir;

    my @entries;

    my $dir_h;
    opendir( $dir_h, $directory ) or $self->logger->logdie( "Can't opendir $directory: $!" );
  FILE:
    while ( defined( my $entry = readdir( $dir_h ) ) ) {
        next unless $entry;
        next if -d $entry;
        next unless $entry =~ m|\.log$|;
        push @entries, $entry;
    }
    closedir( $dir_h );

    for my $entry ( sort @entries ) {
        $self->logger->debug( "Command: found running entry: $entry" );

        my $id = $entry;
        $id =~ s|\.log$||;

        next if $self->_check_process( $id );

        $self->logger->debug( "Command: collecting finish process info for $id" );

        my $logfile = "$directory/$id.log";

        my $output = "";
        if ( -r $logfile ) {
            $self->logger->debug( "Command: Reading command output from logfile: $logfile" );
            open(my $fh, "<", $logfile)
                or die "Couldn't open $logfile for reading: $!\n";
            while ( my $line = <$fh> ) {
                $output .= $line;
            }
            close $fh or die "Error closing file: $!\n";
            chomp $output;
        }

        my $message;
        $message->{command_output} = $output;
        $message->{command_status} = 0;
        $message->{command_signal} = 0;

        my ( $status ) = $self->sqlite->select( { tablename => 'command_queue',
                                                  where     => { queueid => $id, seen => \$is_null, started => \$is_not_null },
                                                  order     => 'id',
                                              } );

        if ( $status ) {
            # deserialize the message data
            if ( $status->{message} ) {
                $status->{message} = Load $status->{message};
            }
            else {
                $self->logger->error( "ERROR: queue entry has no message", YAML::XS::Dump $status );
            }

            $message->{command_status} = $status->{status};
            $message->{command_signal} = $status->{signal};
            $message->{command_queue}  = $id;

            for my $key ( keys %{ $status->{message} } ) {
                unless ( exists $message->{$key} ) {
                    $message->{$key} = $status->{message}->{$key};
                }
            }
            delete $message->{message};

            $self->sqlite->update( 'command_queue',
                                   { seen     => time,
                                 },
                                   { id       => $status->{id} },
                               );

        }
        else {
            $self->logger->error( "ERROR: no status information found about finished process!" );
        }

        if ( $message->{command_status} || $message->{command_signal} ) {
            my $subject = "Command failed: $id";
            if ( $message->{command_status} ) {
                $subject .= " status=$message->{command_status}";
            }
            if ( $message->{command_signal} ) {
                $subject .= " signal=$message->{command_signal}";
            }
            if ( $message->{command_name} ) {
                $subject .= " => $message->{command_name}";
            }
            $message->{subject} = $subject;
            delete $message->{subject_text};
            $message->{status}  = 'CRITICAL';
            $self->logger->error( $subject );
            $self->logger->error( $output );
        }
        else {
            my $subject = "Command succeeded: $id";
            $message->{status}  = 'OK';
            if ( $message->{command_name} ) {
                $subject .= " => $message->{command_name}";
            }
            $message->{subject} = $subject;
            delete $message->{subject_text};
            if ( $message->{command_noresults} ) {
                $self->logger->debug( $subject );
            }
            else {
                $self->logger->info( $subject );
            }
        }

        $message->{lastupdate} = time;

        $self->logger->debug( "Command: collected information about process $id" );

        unless ( $message->{command_noresults} ) {
            push @messages, $message;
        }

        # TODO: hole here where message could be lost after the log is deleted!

        $self->logger->debug( "Unlinking logfile: $logfile" );
        unlink( $logfile );
    }

    $self->logger->debug( "Searching for processes in queue to be started" );

    my @queues;
    eval {                          # try
        @queues = $self->sqlite->select( { tablename => 'command_queue',
                                           fields    => 'DISTINCT queueid'
                                       } );
        1;
    } or do {                       # catch
        $self->logger->debug( "Command: No queue data found" );
        $self->logger->trace( $@ );
    };

  QUEUE:
    for my $queue ( @queues ) {

        my $id = $queue->{queueid};
        next unless $id;

        $self->logger->debug( "Checking queue: $id" );

        my $pidfile = join( "/", $self->logdir, "$id.pid" );
        my $logfile = join( "/", $self->logdir, "$id.log" );

         if ( -r $pidfile ) {
             $self->logger->debug( "Previous process still running: $pidfile" );
             next QUEUE;
         }
         if ( -r $logfile ) {
             $self->logger->debug( "Previous logfile not yet cleaned up: $logfile" );
             next QUEUE;
         }

        my ( $entry ) = $self->sqlite->select( { tablename => 'command_queue',
                                                 where     => { queueid => $id, started => \$is_null, seen => \$is_null },
                                                 order     => 'id',
                                             },
                                           );

        if ( $entry ) {

            $entry->{sqlid} = $entry->{id};
            $entry->{id} = $entry->{queueid};

            # de-serialize the original message data
            if ( $entry->{message} ) {
                $entry->{message} = Load $entry->{message};
            }
            else {
                $self->logger->error( "Warning, no serialized message data for command: queue=$id id=$entry->{sqlid}" );
            }

            if ( my $results = $self->_try_fork( $entry ) ) {

                # TODO: react to message
                #push @messages, { subject => "forked process for queue $id" };

            }
        }

    }

    return unless scalar @messages;

    return \@messages;
}

sub _enqueue {
    my ( $self, $command, $message, $config ) = @_;

    my $id;
    if ( $config->{fork_field} ) {
        $id = $message->{ $config->{fork_field} };
        unless ( $id ) {
            $self->logger->error( "fork_field $config->{fork_field} not defined in message" );
            $id = $config->{fork_field};
        }
        $self->logger->info( "using queue name from $config->{fork_field}: $id" );
    }
    else {
        $id = $config->{fork};
    }

    unless ( -d $self->logdir ) {
        mkpath( $self->logdir );
    }

    my $logfile = join( "/", $self->logdir, "$id.log" );
    my $pidfile = join( "/", $self->logdir, "$id.pid" );

    my $sqlid = $self->sqlite->insert( 'command_queue',
                                       { command    => $command,
                                         pidfile    => $pidfile,
                                         logfile    => $logfile,
                                         queueid    => $id,
                                         lastupdate => time,
                                         message    => Dump( $message ),
                                     },
                                   );

    $self->logger->debug( "Command: queueing for: $id [$sqlid]" );

    $message->{sqlid}          = $sqlid;
    $message->{command_queued} = $id;
    return $message;
}

sub _try_fork {
    my ( $self, $process ) = @_;

    $self->logger->debug( "Forking new process for: $process->{id}" );
    $self->logger->debug( "Command: $process->{command}" );

    my $message = $process->{message} || {};

    if ( my $pid = fork() ) {
        $self->logger->debug( "Fork succeeded, creating pidfile: $process->{pidfile} [$process->{sqlid}]" );

        open(my $fh, ">", $process->{pidfile})
            or die "Couldn't open $process->{pidfile} for writing: $!\n";
        print $fh $pid;
        close $fh or die "Error closing file: $!\n";

        $self->sqlite->update( 'command_queue',
                               { logfile  => $process->{logfile},
                                 logdir   => $self->{logdir},
                                 pidfile  => $process->{pidfile},
                                 started  => time,
                                 pid      => $pid,
                             },
                               { id       => $process->{sqlid} },
                           );


        $message->{pidfile}     = $process->{pidfile};
        $message->{logfile}     = $process->{logfile};
        $message->{command_pid} = $pid;
        $message->{id}          = $process->{id};
        return $message;
    }

    # wu - ugly bug fix - when closing STDIN, it becomes free and
    # may later get reused when calling open (resulting in error
    # 'Filehandle STDIN reopened as $fh only for output'). :/ So
    # instead of closing, just re-open to /dev/null.
    open STDIN, '<', '/dev/null'       or die "$!";

    if ( -r $process->{logfile} ) {
        unlink $process->{logfile};
    }

    open STDOUT, '>>', $process->{logfile} or die "Can't write stdout to $process->{logfile}: $!";
    STDOUT->autoflush(1);

    open STDERR, '>>', $process->{logfile} or die "Can't write stderr to $process->{logfile}: $!";
    STDERR->autoflush(1);

    #setpgrp or die "Can't start a new session: $!";
    setsid or die "Can't start a new session: $!";

    $self->logger->trace( "Launching process: $process->{id}: $process->{command}" );

    # run command capturing output
    my $pid = open my $run, "-|", "$process->{command} 2>&1" or die "Unable to execute $process->{command}: $!";

    $self->sqlite->update( 'command_queue',
                           { childpid => $pid,
                             logfile  => $process->{logfile},
                             logdir   => $self->{logdir},
                             pidfile  => $process->{pidfile},
                         },
                           { id       => $process->{sqlid} },
                       );

    while ( my $line = <$run> ) {
        chomp $line;
        print "$line\n";
    }
    close $run;

    # check exit status
    my $status = 0;
    my $signal = 0;

    unless ( $? eq 0 ) {
        $status = $? >> 8;
        $signal = $? & 127;
        warn "Error running command: $process->{id}: status=$status signal=$signal\n";
    }

    $self->logger->trace( "Process exited: $process->{id}" );

    unlink( $process->{pidfile} );

    $self->sqlite->update( 'command_queue',
                           { status   => $status,
                             signal   => $signal,
                         },
                           { id       => $process->{sqlid} },
                       );

    close STDOUT;
    close STDERR;

    exit;
}

sub _check_process {
    my ( $self, $id ) = @_;

    my $pidfile = join( "/", $self->logdir, "$id.pid" );

    unless ( -r $pidfile ) {
        $self->logger->debug( "Pidfile not found: $pidfile" );
        return;
    }

    open(my $fh, "<", $pidfile)
        or die "Couldn't open $pidfile for reading: $!\n";
    my $pid = <$fh>;
    close $fh or die "Error closing file: $!\n";
    return unless $pid;

    if ( kill 0 => $pid ) {
        $self->logger->debug( "Process $id responded to kill 0: $pid" );
        return $pid;
    }

    $self->logger->debug( "Pidfile exists but pid not active: $pid" );
    unlink( $pidfile );

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Reactor::Command - run an external command using data from the message



=head1 DESCRIPTION

The command reactor can be used to run an external command in response
to some event.

=head1 SYNCHRONOUS

The simplest form of this is to run a command and wait until it
completes.

  - name: play a sound at 5pm
    condition: key matches ^Pulse AND time equals 17:00
    plugin: Command
    config:
      command: /usr/bin/afplay /Users/wu/wubot/sounds/bell.mp3

Note that the entire reactor process will block on the completion of
this command, so you should take care to make sure it is something
that will not hang.


=head1 ASYNCHRONOUS

When you want to run a command that could take more than a few seconds
to complete, you probably want to execute it in the background.  For
that purpose, you can use the 'fork' option in the Command config.

  - name: voice
    condition: contains subject AND urgent is true
    plugin: Command
    config:
      fork: audio
      command_noresults: 1
      command: /usr/bin/say '{$key}' '{$subject_text}'

The 'fork' param specifies the name of a queue.  Wubot will monitor
each named queue and ensure that only one command is active at a time
for each queue.  This allows you to prevent multiple programs that use
the same resource from running simultaneously.  For example, if you
have multiple items that trigger sounds, you can add them all to the
same named queue (I use the name 'audio').  That way you don't end up
with multiple sounds being played at the same time.

The 'command_noresults' option indicates not to send an additional
message when the command completes.

If you want to consult a field on the message for the name of the fork
queue rather than hard-coding it in the configuration, set 'fork' to
1, and then add a config param named 'fork_field' which contains the
name of the field to consult on the message.  If that field is
undefined on the message, then an error will be logged, and the value
of 'fork_field' will be used as a fall-back.

=head1 WORKFLOWS

When a queued command has completed execution, a message will be sent.
You can use that message to trigger additional reactions.  The
completion message will contain all the fields from the original
message, plus the fields:

  command_queue: the command queue from which the command was executed
  command_status: the exit status of the command
  command_signal: signal that terminated the program
  command_output: output of the command

If any of those fields already exist on the message, they will be
overwritten.

Using the named queues and completion messages together, you can build
a workflow, e.g. where one queue is downloading items, a second queue
is decompressing them, and a third queue is removing the original
archives if the decompression was successful.  By using a different
queue name for each process, you ensure that one process is doing each
task at a time, as long as there is something in the queue for it to
be doing.

I do plan to write a guide with better examples in the near future.

=head1 SECURITY WARNINGS

Extreme care must be exercised when using tainted data in your
commands!  If your entire command is hard-coded, then there is not
much of a security risk:

  command: /usr/bin/afplay /Users/wu/wubot/sounds/bell.mp3

However if you are building a command that references fields on the
message, then if someone added a command to your queue that contained
a scary message field, then that command could be executed as you.
This could do scary things such as:

  rm -rf ~/*

This can be especially dangerous if you are running wubot on multiple
hosts that are communicating over XMPP.

You can use reactor conditions to check your data, or reactor plugins
such as TransformField to detaint your data before passing it in to an
external command.


=head1 LIMITATIONS

It is not yet possible to specify a timeout for a command queue.  So
if a program hangs indefinitely, the queue will get stuck.  This is on
the todo list (patches welcome!).

The queues are checked each time the reactor's monitor() method is
called.  Currently this is once ever 15 seconds.  So there could be up
to a 15 second delay in-between the time when your command is added to
the queue and the time it is executed.  The reactor's monitor() method
is only called in the wubot-reactor process.  So if you define any
'react' method with the Command plugin on a monitor config, the
wubot-monitor process will never try to execute items in the queue.

You must have at least one rule in your reactor config that uses the
Command plugin, or the wubot-reactor will never check the queue.


=head1 SUBROUTINES/METHODS

=over 8

=item react( $message, $config )

The standard reactor plugin react() method.

=item monitor()

The standard reactor monitor() method.

TODO: exclude this from Test::Pod::Coverage

=back

=begin Pod::Coverage

  WNOHANG

=end Pod::Coverage
