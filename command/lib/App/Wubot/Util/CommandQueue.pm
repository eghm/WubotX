package App::Wubot::Util::CommandQueue;
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

=head1 NAME

App::Wubot::Util::CommandQueue

=head1 SYNOPSIS

    use App::Wubot::Util::CommandQueue;

=head1 DESCRIPTION

Prototype.

=cut


has 'dbfile' => ( is      => 'rw',
                  isa     => 'Str',
                  lazy    => 1,
                  default => sub {
                      return join( "/", $ENV{HOME}, "wubot", "sqlite", "commandqueue.sql" );
                  },
              );

has 'sqlite'    => ( is       => 'ro',
                     isa      => 'App::Wubot::SQLite',
                     lazy     => 1,
                     default  => sub {
                         my $self = shift;
                         $self->logger->warn( "Command: connecting to sqlite db: ", $self->dbfile );
                         return App::Wubot::SQLite->new( { file => $self->dbfile } );
                     },
               );

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

has 'logdir'   => ( is       => 'ro',
                    isa      => 'Str',
                    lazy     => 1,
                    default  => sub {
                        my $self = shift;
                        my $directory = join( "/", $ENV{HOME}, "wubot", "commands" );
                        unless ( -d $directory ) {
                            mkpath( $directory );
                        }
                        return $directory;
                    },
                );

has 'schema'   => ( is      => 'ro',
                    isa     => 'HashRef',
                    lazy    => 1,
                    default => sub {
                        return { id           => 'INTEGER PRIMARY KEY AUTOINCREMENT',
                                 command      => 'TEXT',
                                 command_desc => 'VARCHAR(128)',
                                 queue        => 'VARCHAR(32)',
                                 subject      => 'VARCHAR(256)',
                                 status       => 'VARCHAR(16)',
                                 started      => 'INTEGER',
                                 added        => 'INTEGER',
                                 ended        => 'INTEGER',
                                 processed    => 'INTEGER',
                                 pid          => 'INTEGER',
                                 exit_status  => 'INTEGER',
                                 exit_signal  => 'INTEGER',
                                 output       => 'TEXT',
                             };
                    },
                );

my $is_not_null = "IS NOT NULL";

=head1 SUBROUTINES/METHODS

=over 8

=item $obj->xyz()

TODO: documentation this method

=cut

sub run {
    my ( $self, $queue ) = @_;

    # check if command already in queue
    #   check if command is complete
    #   get return status

    # start next item in queue


}

sub build_command {
    my ( $self, $command, $message ) = @_;

    my $template = Text::Template->new(TYPE => 'STRING', SOURCE => $command );
    $command = $template->fill_in( HASH => $message );
    $self->logger->debug( "COMMAND: $command\n" );

    #$command =~ s|\\|\\\\|g;
    #$command =~ s|\>|\\>|g;

    return $command
}

sub enqueue {
    my ( $self, $command, $queue, $desc ) = @_;

    unless ( $command ) {
        $self->logger->logdie( "ERROR: enqueue called with no command" );
    }

    unless ( $queue ) {
        $self->logger->logdie( "ERROR: enqueue called with no queue" );
    }

    my $results_h = { command      => $command,
                      queue        => $queue,
                      added        => time,
                      command_desc => $desc,
                  };

    $results_h->{id} = $self->sqlite->insert( 'command_queue',
                                              $results_h,
                                              $self->schema
                                          );

    $self->logger->debug( "Command: queueing for: $queue [$results_h->{id}]" );

    return $results_h;
}

sub get_next {
    my ( $self, $queue ) = @_;

    my ( $results_h ) = $self->sqlite->select( { tablename => 'command_queue',
                                                 where     => 'started IS NULL',
                                                 order     => 'id ASC',
                                                 schema    => $self->schema,
                                             } );

    return $results_h;
}

sub get_item {
    my ( $self, $id ) = @_;

    my ( $results_h ) = $self->sqlite->select( { tablename => 'command_queue',
                                                 where     => { id => $id },
                                                 schema    => $self->schema,
                                             } );

    return $results_h;
}

sub spawn {
    my ( $self, $id ) = @_;

    unless ( $id ) {
        $self->logger->logdie( "ERROR: spawn() called but id not specified" );
    }

    my ( $command_h ) = $self->sqlite->select( { tablename => 'command_queue',
                                                 where     => { id => $id },
                                                 schema    => $self->schema,
                                           } );

    unless ( $command_h ) {
        $self->logger->logdie( "ERROR: id $id not found in command_queue" );
    }

    my $queue = $command_h->{queue};

    $self->logger->debug( "Forking: $command_h->{command}" );

    my $logfile = join( "/", $self->logdir, "$queue.log" );

    if ( my $pid = fork() ) {

        $self->logger->debug( "$queue: Forked child process: $pid" );

        $command_h->{pid} = $pid;

        $self->sqlite->update( 'command_queue',
                               { pid     => $pid, started => time },
                               { id      => $id  },
                               $self->schema
                           );

        return $command_h;
    }

    # wu - ugly bug fix - when closing STDIN, it becomes free and
    # may later get reused when calling open (resulting in error
    # 'Filehandle STDIN reopened as $fh only for output'). :/ So
    # instead of closing, just re-open to /dev/null.
    open STDIN, '<', '/dev/null'       or die "$!";

    open STDOUT, '>>', $logfile or die "Can't write stdout to $logfile: $!";
    STDOUT->autoflush(1);

    open STDERR, '>>', $logfile or die "Can't write stderr to $logfile: $!";
    STDERR->autoflush(1);

    #setpgrp or die "Can't start a new session: $!";
    setsid or die "Can't start a new session: $!";

    # run command capturing output
    my $pid = open my $run, "-|", "$command_h->{command} 2>&1" or die "Unable to execute $command_h->{command}: $!";

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
        warn "Error running command: $command_h->{id}: status=$status signal=$signal\n";
    }

    undef $/;
    open(my $fh, "<", $logfile)
        or die "Couldn't open $logfile for reading: $!\n";
    my $output = <$fh>;
    close $fh or die "Error closing file: $!\n";

    $self->sqlite->update( 'command_queue',
                           { exit_status => $status,
                             exit_signal => $signal,
                             ended       => time,
                             output      => $output,
                         },
                           { id          => $command_h->{id} },
                           $self->schema,
                       );

    close STDOUT;
    close STDERR;

    unlink $logfile;

    exit;
}

sub monitor_queue {
    my ( $self, $queue ) = @_;

    unless ( $queue ) {
        $self->logger->logdie( "ERROR: monitor_queue called without queue name" );
    }

    # clean up any child processes that have exited
    $self->logger->trace( "Command: killing zombies" );
    waitpid(-1, WNOHANG);

    # in theory there should only be one item here, but handle
    # multiple just in case
    my @running = $self->sqlite->select( { tablename => 'command_queue',
                                            where     => { queue     => $queue,
                                                           pid       => \$is_not_null,
                                                           processed => undef,
                                                       },
                                            schema    => $self->schema,
                                        } );

    my @messages;

    my $active;

  COMMAND:
    for my $command_h ( @running ) {

        my $pid = $command_h->{pid};

        # check if process is still active
        $self->logger->debug( "Checking if process $pid is still active" );
        if ( kill 0 => $pid ) {
            $active = 1;
            $self->logger->debug( "PID $pid is active" );
            next COMMAND;
        }

        $self->logger->debug( "Processing results of pid: $pid" );

        my $now = time;

        if ( $command_h->{exit_status} ) {
            $self->logger->debug( "Command failed" );
            $command_h->{subject}   = "$command_h->{queue}: Command FAIL: $command_h->{exit_status}";
            $command_h->{status}    = 'CRITICAL';
        }
        else {
            $self->logger->debug( "Command succeeded" );
            $command_h->{subject}   = "$command_h->{queue}: Command OK";
            $command_h->{status}    = 'OK';
        }

        if ( $command_h->{command_desc} ) {
            $command_h->{subject} .= ": $command_h->{command_desc}";
        }

        # mark item as processed
        $self->sqlite->update( 'command_queue',
                               { processed  => $now,
                                 lastupdate => $now,
                                 status     => $command_h->{status},
                                 subject    => $command_h->{subject},
                             },
                               { id         => $command_h->{id} },
                               $self->schema,
                           );

        $command_h->{processed} = $now;


        push @messages, $self->get_item( $command_h->{id} );
    }

    unless ( $active ) {

        $self->logger->debug( "Inactive queue: searching for next task in queue: $queue" );

        my $command_h = $self->get_next( $queue );

        if ( $command_h ) {

            $self->logger->debug( "Spawning command in queue: $queue" );

            $self->spawn( $command_h->{id} );

            my $desc = $command_h->{command_desc} ? $command_h->{command_desc} : "new command";

            $command_h->{subject} = "$command_h->{queue}: Spawned: $desc";

            push @messages, $command_h;

        }
    }

    return @messages;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=back
