package App::Wubot::Util::Notifications;
use Moose;

# VERSION

use App::Wubot::Logger;
use App::Wubot::SQLite;

has 'sql'    => ( is      => 'ro',
                  isa     => 'App::Wubot::SQLite',
                  lazy    => 1,
                  default => sub {
                      App::Wubot::SQLite->new( { file => $_[0]->dbfile } );
                  },
              );

has 'dbfile' => ( is      => 'rw',
                  isa     => 'Str',
                  lazy    => 1,
                  default => sub {
                      return join( "/", $ENV{HOME}, "wubot", "sqlite", "notify.sql" );
                  },
              );

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

sub update {
    my ( $self, $item, $where ) = @_;

    $self->sql->insert_or_update( 'notifications',
                                  $item,
                                  $where
                              );

}

sub insert_tag {
    my ( $self, $id, $tag ) = @_;

    $self->sql->insert( 'tags',
                        { remoteid => $id, tag => $tag, tablename => 'notifications', lastupdate => time },
                    );

}

sub get_item_tags {
    my ( $self, $id ) = @_;

    my @tags;

    $self->sql->select( { tablename => 'tags',
                          fieldname => 'tag',
                          where     => { remoteid => $id },
                          order     => 'tag',
                          callback  => sub { my $entry = shift;
                                             push @tags, $entry->{tag};
                                         },
                      } );

    return @tags;
}

sub get_all_tags {
    my ( $self ) = @_;

    my $tags_h;

    $self->sql->select( { tablename => 'tags',
                          fieldname => 'tag',
                          callback  => sub { my $entry = shift;
                                             $tags_h->{ $entry->{tag} }++;
                                         },
                      } );

    return $tags_h;
}

sub mark_seen {
    my ( $self, $ids, $time ) = @_;

    unless ( $time ) { $time = time }

    my @seen;

    if ( ref $ids eq "ARRAY" ) {
        @seen = @{ $ids }
    }
    elsif ( $ids =~ m|,| ) {
        @seen = split /,/, $ids;
    }
    else {
        @seen = ( $ids );
    }

    $self->sql->update( 'notifications',
                        { seen => $time   },
                        { id   => \@seen },
                    );
}

sub get_tagged_ids {
    my ( $self, $tag ) = @_;

    my @ids;

    my $select = { tablename => 'tags',
                   fieldname => 'remoteid',
                   callback  => sub {
                       my $row = shift;
                       push @ids, $row->{remoteid};
                   },
               };

    if ( $tag ) {
        $select->{where} = { tag => $tag };
    }

    $self->sql->select( $select );

    return @ids;
}

sub get_item_by_id {
    my ( $self, $id ) = @_;

    my ( $item ) = $self->sql->select( { tablename => 'notifications',
                                         where     => { id => $id },
                                     } );

    # todo: fall back to notifications_archive if does not exist in notifications table!
    # todo: option to disable fallback, e.g. for 'archive' method

    return $item;
}

sub select {
    my ( $self, $select_h ) = @_;

    $select_h->{tablename} = 'notifications';

    my ( $item ) = $self->sql->select( $select_h );

    return ( $item );
}

sub archive {
    my ( $self, $id ) = @_;

    # todo: do this as a single transaction!

    $self->logger->info( "Archiving: $id" );

    $self->logger->debug( "Selecting id: $id" );
    my ( $item ) = $self->get_item_by_id( $id );

    unless ( $item->{seen} ) {
        $self->logger->warn( "\tSkipping unseen item!" );
    }

    $self->logger->debug( "Inserting into archive: $id" );
    $self->sql->insert_or_update( 'notifications_archive', $item, { id => $id } );

    $self->logger->debug( "Deleting: $id" );
    $self->sql->delete( 'notifications', { id => $id } );
}

sub vacuum {
    my ( $self ) = @_;

    $self->sql->vacuum();
}

1;
