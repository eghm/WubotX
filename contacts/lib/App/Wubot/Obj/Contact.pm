package App::Wubot::Obj::Contact;
use Moose;

use App::Wubot::Logger;
use App::Wubot::SQLite;

has dbfile       => ( is      => 'rw',
                      isa     => 'Str',
                      lazy    => 1,
                      default => sub {
                          return join( "/", $ENV{HOME}, "wubot", "sqlite", "contacts.sql" );
                      },
                  );

has username     => ( is       => 'ro',
                      isa      => 'Str',
                      required => 1,
                  );

has first_name   => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                  );

has last_name    => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                  );

has full_name    => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                  );

has nick         => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                  );

has color        => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                  );

has phone_mobile => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                  );

has phone_work   => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                    );

has phone_home   => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                  );

has category     => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                  );

has link         => ( is       => 'rw',
                      isa      => 'Maybe[Str]',
                  );

with 'App::Wubot::Obj::Roles::Obj';

sub get_contact_hash {
    my ( $self ) = @_;

    my $contact_h;

    for my $field ( qw( username first_name middle_name last_name full_name
                        nick birthday color company position category
                        phone_work phone_mobile phone_home
                        aim link image notes ) ) {

        if ( $self->can( $field ) ) {
            $contact_h->{ $field } = $self->$field;
        }
    }

    return $contact_h;
}

sub update {
    my ( $self ) = @_;

    $self->logger->debug( "Calling update method for contact: ", $self->username );

    my $contact_h = $self->get_contact_hash;

    my ( $id ) = $self->sql->insert_or_update( 'contacts', $contact_h, { username => $self->username } );

    $self->logger->debug( "Updated user id: $id" );
}


1;
