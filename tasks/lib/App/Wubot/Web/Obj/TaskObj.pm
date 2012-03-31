package App::Wubot::Web::Obj::TaskObj;
use Moose;

# VERSION

use Date::Manip;
use HTML::Strip;
use POSIX qw(strftime);
use Text::Wrap;

use App::Wubot::Logger;
use App::Wubot::SQLite;
use App::Wubot::Util::Taskbot;
use App::Wubot::Util::TimeLength;

has 'taskbot'          => ( is => 'ro',
                            isa => 'App::Wubot::Util::Taskbot',
                            lazy => 1,
                            default => sub {
                                return App::Wubot::Util::Taskbot->new();
                            },
                        );

has 'db_hash'          => ( is => 'ro',
                            isa => 'HashRef',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                unless ( $self->{taskid} ) {
                                    $self->logger->logdie( "ERROR: no data provided and no taskid set" );
                                }
                                my ( $task_h ) = $self->sql->select( { tablename => 'taskbot',
                                                                       where     => { taskid => $self->taskid },
                                                                   } );
                                return $task_h;
                            },
                        );

has 'status'           => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{status} || "TODO";
                            }
                        );

has 'status_pretty'    => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                my $status = $self->status;
                                if ( $status eq "TODO" ) {
                                    my $color = $self->colors->get_color( 'white' );
                                    $status = "<font color='$color'>TODO</font>";
                                } elsif ( $status eq "DONE" ) {
                                    my $color = $self->colors->get_color( 'green' );
                                    $status = "<font color='green'>DONE</font>";
                                }
                                return $status;
                            }
                        );

has 'scheduled'        => ( is => 'ro',
                            isa => 'Maybe[Num]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{scheduled};
                            }
                        );

has 'end'              => ( is => 'ro',
                            isa => 'Maybe[Num]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return unless $self->scheduled;

                                my $length = $self->timelength->get_seconds( $self->duration );

                                return $self->scheduled + $length;
                            },
                        );

has 'scheduled_color'  => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;

                                return $self->display_color unless $self->scheduled;

                                my $now = time;

                                if ( $now > $self->scheduled ) {
                                    return $self->colors->get_color( "red" );
                                }

                                return $self->timelength->get_age_color( abs( $now - $self->scheduled ) );
                            }
                        );

has 'scheduled_pretty' => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                my $scheduled = $self->scheduled;
                                return "" unless $scheduled;
                                return strftime( '%Y-%m-%d %H:%M', localtime( $scheduled ) );
                            }
                        );

has 'scheduled_time'   => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                my $scheduled = $self->scheduled;
                                return "" unless $scheduled;
                                return strftime( '%l:%M %p', localtime( $scheduled ) );
                            }
                        );

has 'scheduled_age'    => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                my $scheduled = $self->scheduled;
                                return "" unless $scheduled;
                                return $self->timelength->get_human_readable( time - $scheduled );
                            }
                        );

has 'title'            => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{title};
                            }
                        );

has 'priority'         => ( is => 'ro',
                            isa => 'Num',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{priority} || 50;
                            }
                        );

has 'priority_display' => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;

                                my $redir = $self->redir;

                                return "" unless $self->taskid;

                                my $link = join( "/", "/taskbot", "item", $self->taskid );
                                $link .= "?redir=$redir&priority";

                                my $link_minus = join( "=", $link, $self->priority - 5 );
                                my $link_plus  = join( "=", $link, $self->priority + 5 );

                                my $return = join( " ",
                                                   $self->priority,
                                                   "<a href='$link_minus'>-</a>",
                                                   "<a href='$link_plus'>+</a>",
                                               );

                                return $return;
                            }
                        );

has 'category'         => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{category};
                            }
                        );

has 'duration'         => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{duration};
                            }
                        );

has 'recurrence'       => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{recurrence};
                            }
                        );

has 'recurrence_color'  => ( is => 'ro',
                             isa => 'Maybe[Str]',
                             lazy => 1,
                             default => sub {
                                 my $self = shift;

                                 return $self->display_color unless $self->recurrence;

                                 my $seconds;

                                 eval {                          # try
                                     $seconds = $self->timelength->get_seconds( $self->recurrence );
                                     1;
                                 } or do {                       # catch
                                     return $self->display_color;
                                 };

                                 return $self->display_color unless $seconds;

                                 return $self->timelength->get_age_color( $seconds );
                            }
                        );


has 'body'             => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return unless $self->taskid;

                                return $self->taskbot->read_body( $self->taskid );
                            },
                        );

has 'has_body'         => ( is => 'ro',
                            isa => 'Bool',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return unless $self->taskid;
                                my $path = $self->taskbot->get_path( $self->taskid );
                                return 1 if -r $path;
                                return;
                            },
                        );

has 'pre_body'         => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;

                                my $body = $self->body;

                                return unless $body;

                                $body =~ s|\<br\>|\n\n|g;
                                $Text::Wrap::columns = 120;
                                my $hs = HTML::Strip->new();
                                $body = $hs->parse( $body );
                                $body =~ s|\xA0| |g;
                                $body = fill( "", "", $body);

                                utf8::decode( $body );

                                return $body;
                            }
                        );

has 'taskid'           => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{taskid};
                            }
                        );

has 'timer'            => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return "" unless $self->scheduled;

                                my $now = time;
                                if ( $self->scheduled < $now && $self->end > $now ) {
                                    return $self->timelength->get_human_readable( $self->end - time );
                                }

                                return $self->timelength->get_human_readable( $self->scheduled - time );
                            }
                        );

has 'redir'            => ( is => 'ro',
                            isa => 'Str',
                            default => "list",
                        );

has 'timer_color'      => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->display_color unless $self->scheduled;

                                my $now = time;

                                if ( $self->end < $now ) {
                                    return $self->colors->get_color( "red" );
                                }

                                if ( $self->scheduled < $now && $self->end > $now ) {
                                    return $self->colors->get_color( "darkgreen" );
                                }

                                return $self->timelength->get_age_color( abs( $self->scheduled - time ) );
                            }
                        );

has 'timer_display'    => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;

                                return "" unless $self->timer;

                                my $redir = $self->redir;

                                my $link = join( "/", "/taskbot", "item", $self->taskid );
                                $link .= "?redir=$redir&scheduled";

                                my $link_minus = join( "=", $link, $self->scheduled - 24*60*60 );
                                my $link_plus  = join( "=", $link, $self->scheduled + 24*60*60 );

                                my $return = join( " ",
                                                   $self->timer,
                                                   "<a href='$link_minus'>-</a>",
                                                   "<a href='$link_plus'>+</a>",
                                               );

                                return $return;
                            }
                        );

has 'sound'            => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{sound};
                            }
                        );

has 'lastdone'       => ( is => 'ro',
                          isa => 'Maybe[Str]',
                          lazy => 1,
                          default => sub {
                              my $self = shift;
                              return $self->db_hash->{lastdone};
                          }
                      );

has 'lastdone_age'     => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return unless $self->lastdone;
                                return $self->timelength->get_human_readable( time - $self->lastdone );
                            }
                        );

has 'lastdone_color' => ( is => 'ro',
                          isa => 'Str',
                          lazy => 1,
                          default => sub {
                              my $self = shift;
                              return $self->display_color unless $self->lastdone;
                              return $self->timelength->get_age_color( abs( $self->lastdone - time ) );
                          }
                      );

with 'App::Wubot::Web::Obj::Roles::Obj';

1;
