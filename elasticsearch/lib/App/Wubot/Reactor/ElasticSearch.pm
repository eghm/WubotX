package App::Wubot::Reactor::ElasticSearch;
use Moose;

# VERSION

use ElasticSearch;

use App::Wubot::Logger;

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

has 'es'      => ( is => 'ro',
                   isa => 'ElasticSearch',
                   default => sub {
                       return ElasticSearch->new();
                   },
               );

sub react {
    my ( $self, $message, $config ) = @_;

    unless ( $config->{id_field} ) {
        $self->logger->error( "ElasticSearch Reactor: 'id_field' not found in config" );
        return $message;
    }
    my $id    = $message->{ $config->{id_field} };
    unless ( $id ) {
        $self->logger->error( "ElasticSearch Reactor: 'id_field' $config->{id_field} not found in message" );
        return $message;
    }

    my $type  = $config->{type};
    unless ( $type ) {
        $self->logger->error( "ElasticSearch Reactor: 'type' not found in config" );
        return $message;
    }

    unless ( $config->{index_field} ) {
        $self->logger->error( "ElasticSearch Reactor: 'index_field' not found in config" );
        return $message;
    }
    my $index = $message->{ $config->{index_field} };
    unless ( $index ) {
        $self->logger->error( "ElasticSearch Reactor: 'index_field' $config->{index_field} not found in message" );
        return $message;
    }

    $self->es->index(
        index => $index,
        type  => $type,
        id    => $id,
        data  => $message,
    );

    return $message;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Reactor::ElasticSearch - insert a message into ElasticSearch

=head1 DESCRIPTION

TODO: More to come...


=head1 SUBROUTINES/METHODS

=over 8

=item react( $message, $config )

The standard reactor plugin react() method.

=back
