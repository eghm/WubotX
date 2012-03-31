package App::Wubot::Web::ContactsWeb;
use strict;
use warnings;

# VERSION

use Mojo::Base 'Mojolicious::Controller';

use App::Wubot::Logger;
use App::Wubot::Obj::ContactList;
use App::Wubot::SQLite;
use App::Wubot::Util::Colors;
use App::Wubot::Util::TimeLength;

=head1 NAME

App::Wubot::Web::ContactsWeb - web interface for contacts

=head1 CONFIGURATION


=head1 DESCRIPTION

=cut


=head1 SUBROUTINES/METHODS

=over 8

=item item


=cut

sub item {
    my ( $self ) = @_;

    $self->stash( 'item', { a => 1, b => 2 } );

    $self->render( template => 'contacts.item' );
};

=item list

=cut

sub list {
    my ( $self ) = @_;

    my $contactlist = App::Wubot::Obj::ContactList->new();

    my $list_h = $contactlist->list();

    for my $key ( keys %{ $list_h } ) {
        $self->stash( $key, $list_h->{$key} );
    }

    $self->render( template => 'contacts.list' );
}

1;

__END__


=back
