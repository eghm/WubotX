package App::Wubot::Util::Taskbot;
use Moose;

# VERSION

use Date::Manip;
use POSIX qw(strftime);

use App::Wubot::Logger;
use App::Wubot::SQLite;
use App::Wubot::Util::TimeLength;

=head1 NAME

App::Wubot::Util::Taskbot

=head1 SYNOPSIS

    use App::Wubot::Util::Taskbot;

=head1 DESCRIPTION

Prototype.

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
                      return join( "/", $ENV{HOME}, "wubot", "sqlite", "taskbot.sql" );
                  },
              );

has 'bodydir' => ( is      => 'rw',
                  isa     => 'Str',
                  lazy    => 1,
                  default => sub {
                      my $directory = join( "/", $ENV{HOME}, "wubot", "taskbot" );
                      unless ( -d $directory ) { mkpath( $directory ) }
                      return $directory;
                  },
              );

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

has 'timelength' => ( is => 'ro',
                      isa => 'App::Wubot::Util::TimeLength',
                      lazy => 1,
                      default => sub {
                          return App::Wubot::Util::TimeLength->new();
                      },
                  );

=head1 SUBROUTINES/METHODS

=over 8

=item $obj->update_taskid( $taskid, $item )

TODO: documentation this method

=cut


sub get_task {
    my ( $self, $taskid ) = @_;

    unless ( $taskid ) {
        $self->logger->logdie( "ERROR: get_task called but taskid not specified" );
    }

    my ( $task_h ) = $self->sql->select( { tablename => 'taskbot',
                                           where     => { taskid => $taskid },
                                       } );

    unless ( $task_h ) {
        $self->logger->logdie( "ERROR: task not found: $taskid" );
    };

    my $body = $self->read_body( $taskid );
    if ( $body ) {
        $task_h->{body} = $body;
    }

    return $task_h;
}

sub check_schedule {
    my ( $self, $options ) = @_;

    my @tasks;

    my $limit = $options->{limit} || 20;

    # default to a 24-hour window
    my $now = time;
    my $end = time + 60*60*24;

    my %query = ( tablename => 'taskbot',
                  order     => [ 'scheduled', 'priority DESC', 'lastupdate DESC' ],
                  limit     => $limit,
                  where     => { status => 'TODO', scheduled => { '>=' => $now, '<=' => $end } },
                  callback  => sub {
                      my $row = shift;
                      push @tasks, $row;
                  },
              );

    $self->sql->select( \%query );

    return @tasks;

}

sub create_task {
    my ( $self, $task_h ) = @_;

    unless ( $task_h->{lastupdate} ) {
        $task_h->{lastupdate} = time;
    }

    unless ( $task_h->{type} ) {
        $task_h->{type} = "taskbot";
    }

    my ( $id ) = $self->sql->insert( 'taskbot',
                                        $task_h
                                    );

    $task_h->{taskid} = join( "-", uc( $task_h->{type} ), $id );

    $self->sql->update( 'taskbot',
                        { taskid => $task_h->{taskid} },
                        { id     => $id }
                    );

    if ( $task_h->{body} ) {
        $self->write_body( $task_h->{taskid}, $task_h->{body} );
    }

    return $task_h;
}


sub write_body {
    my ( $self, $taskid, $body ) = @_;

    unless ( $taskid ) {
        die "ERROR: write_body called without taskid"
    }
    unless ( $body ) {
        die "ERROR: write_body called without body"
    }

    my $path = $self->get_path( $taskid );

    open(my $fh, ">", $path)
        or die "Couldn't open $path for writing: $!\n";
    print $fh $body;
    close $fh or die "Error closing file: $!\n";

    return 1;
}

sub read_body {
    my ( $self, $taskid ) = @_;

    unless ( $taskid ) {
        die "ERROR: read_body called without taskid"
    }

    my $path = $self->get_path( $taskid );
    return unless -r $path;

    local undef $/;
    open(my $fh, "<", $path)
        or die "Couldn't open $path for reading: $!\n";
    my $body = <$fh>;
    close $fh or die "Error closing file: $!\n";

    return $body;
}


sub open {
    my ( $self, $taskid ) = @_;

    unless ( $taskid ) {
        die "ERROR: open() called but taskid not specified"
    }

    my ( $path, $filename ) = $self->get_path( $taskid );

    my $emacs_foo = qq{ (progn (org-open-link-from-string "[[$path]]" )(pop-to-buffer "$filename")(delete-other-windows)(save-buffer)(raise-frame)) };

    my $command = qq(emacsclient --socket-name /tmp/emacs501/server -e '$emacs_foo' &);

    system( $command );
}

sub get_path {
    my ( $self, $taskid ) = @_;

    unless ( $taskid ) {
        die "ERROR: open() called but taskid not specified"
    }

    # clean task id
    $taskid =~ tr/a-zA-Z0-9\-//cd;

    my $filename = join( ".", $taskid, "org" );

    my $path = join( "/", $self->bodydir, $filename );

    if ( wantarray ) {
        return ( $path, $filename );
    }
    else {
        return $path;
    }
}

# sub mark_done {
#     my ( $self, $taskid ) = @_;

#     my $task_h = $self->get_task( $taskid );

#     return unless $task_h->{status} eq "TODO";

#     $task_h->{status}   = "DONE";
#     $task_h->{lastdone} = time;

#     if ( $task_h->{recurrence} ) {
#         $task_h->{status} = "TODO";

#         my $next = $timelength->get_seconds( $task_h->{recurrence} );

#         if ( $task_orig->{scheduled} ) {
#             $task_h->{scheduled} = $task_orig->{scheduled} + $next;
#         }
#     }

#     $self->sql->update( 'taskbot',
#                         $task_h,
#                         { taskid => $task_h->{taskid} }
#                     );

#     return $task_h;
# }

__PACKAGE__->meta->make_immutable;

1;

__END__

=back
