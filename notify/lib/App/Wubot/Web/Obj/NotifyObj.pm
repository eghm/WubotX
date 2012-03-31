package App::Wubot::Web::Obj::NotifyObj;
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

has 'notifications'    => ( is => 'ro',
                            isa => 'App::Wubot::Util::Notifications',
                            lazy => 1,
                            default => sub {
                                return App::Wubot::Util::Notifications->new();
                            },
                        );

has 'timelength'       => ( is => 'ro',
                            isa => 'App::Wubot::Util::TimeLength',
                            lazy => 1,
                            default => sub {
                                return App::Wubot::Util::TimeLength->new();
                            },
                        );

has 'db_hash'          => ( is => 'ro',
                            isa => 'HashRef',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                unless ( $self->{id} ) {
                                    $self->logger->logdie( "ERROR: no data provided and no taskid set" );
                                }
                                my ( $task_h ) = $self->sql->select( { tablename => 'notifications',
                                                                       where     => { id => $self->id },
                                                                   } );
                                return $task_h;
                            },
                        );

has 'subject'          => ( is => 'ro',
                            isa => 'Str',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                my $subject = $self->db_hash->{subject};
                                utf8::decode( $subject );
                                return $subject;
                            }
                        );

has 'subject_text'     => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;

                                my $subject = $self->db_hash->{subject_text} || $self->db_hash->{subject};

                                return unless $subject;

                                utf8::decode( $subject );
                                return $subject;
                            }
                        );

has 'score'            => ( is => 'ro',
                            isa => 'Maybe[Num]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{score};
                            }
                        );

has 'icon'             => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                my $icon = $self->db_hash->{icon};
                                $icon =~ s|^.*\/||;
                                return $icon;
                            }
                        );

has 'mailbox'          => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{mailbox} || "null";
                            }
                        );

has 'body'            => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                my $body = $self->db_hash->{body};
                                utf8::decode( $body );
                                return $body;
                            }
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

                                return $body;
                            }
                        );

has 'key'              => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                return $self->db_hash->{key};
                            }
                        );

has 'key1'             => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                if ( $self->key =~ m|^(.*?)\-(.*)| ) {
                                    return $1;
                                }
                                return $self->key;
                            }
                        );

has 'key2'             => ( is => 'ro',
                            isa => 'Maybe[Str]',
                            lazy => 1,
                            default => sub {
                                my $self = shift;
                                if ( $self->key =~ m|^(.*?)\-(.*)| ) {
                                    return $2;
                                }
                                return;
                            }
                        );


with 'App::Wubot::Web::Obj::Roles::Obj';

1;
