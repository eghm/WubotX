package App::Wubot::Obj::ContactList;
use Moose;

use App::Wubot::Logger;
use App::Wubot::Obj::Contact;
use App::Wubot::SQLite;
use App::Wubot::Util::TimeLength;

has sql          => ( is      => 'ro',
                      isa     => 'App::Wubot::SQLite',
                      lazy    => 1,
                      default => sub {
                          return App::Wubot::SQLite->new( { file => $_[0]->dbfile } );
                      },
                  );

has dbfile       => ( is      => 'rw',
                      isa     => 'Str',
                      lazy    => 1,
                      default => sub {
                          return join( "/", $ENV{HOME}, "wubot", "sqlite", "contacts.sql" );
                      },
                  );

has logger       => ( is => 'ro',
                      isa => 'Log::Log4perl::Logger',
                      lazy => 1,
                      default => sub {
                          return Log::Log4perl::get_logger( __PACKAGE__ );
                      },
                  );

has timelength   => ( is => 'ro',
                      isa => 'App::Wubot::Util::TimeLength',
                      lazy => 1,
                      default => sub {
                          return App::Wubot::Util::TimeLength->new();
                      },
                  );

sub list {
    my ( $self ) = @_;

    my @contacts;

    my $query = {
        tablename => 'contacts',
        order     => [ 'username ASC' ],
        callback  => sub {
            my $row = shift;
            push @contacts, App::Wubot::Obj::Contact->new( { %$row, sql => $self->sql } );
        },
    };

    $self->sql->select( $query );

    return {
        headers   => [qw/username nick full_name phone_mobile phone_work phone_home category/ ],
        body_data => \@contacts,
    };
}

1;
