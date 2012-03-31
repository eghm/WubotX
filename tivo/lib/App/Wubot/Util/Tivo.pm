package App::Wubot::Util::Tivo;
use Moose;

# VERSION

use Date::Manip;
use POSIX qw(strftime);
use YAML;
use File::Path;

use App::Wubot::Logger;
use App::Wubot::Util::CommandQueue;
use App::Wubot::Util::TimeLength;

=head1 NAME

App::Wubot::Util::Tivo

=head1 SYNOPSIS

    use App::Wubot::Util::Tivo;

=head1 DESCRIPTION

Prototype.


=cut

has 'dbfile' => ( is      => 'rw',
                  isa     => 'Str',
                  lazy    => 1,
                  default => sub {
                      return join( "/", $ENV{HOME}, "wubot", "sqlite", "tivo.sql" );
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

has 'table'  => ( is       => 'ro',
                  isa      => 'Str',
                  default  => 'recorded',
              );

has 'schema'  => ( is       => 'ro',
                   isa      => 'Str',
                   default  => 'tivo.recorded',
               );

has 'idfield' => ( is       => 'ro',
                   isa      => 'Str',
                   default  => 'tivoid',
               );

has 'queue'   => ( is => 'ro',
                   isa => 'App::Wubot::Util::CommandQueue',
                   lazy => 1,
                   default => sub {
                       my $self = shift;
                       # store the tivo queue
                       return App::Wubot::Util::CommandQueue->new( dbfile => $self->dbfile );
                   },
               );


with 'App::Wubot::Util::Roles::Tables';


=head1 SUBROUTINES/METHODS

=over 8

=item $obj->xyz()

TODO: documentation this method

=cut

sub get_item {
    my ( $self, $tivoid ) = @_;

    unless ( $tivoid ) {
        $self->logger->logdie( "ERROR: get_item called but tivoid not specified" );
    }

    my ( $item_h ) = $self->sql->select( { tablename => 'recorded',
                                           where     => { tivoid => $tivoid },
                                       } );

    unless ( $item_h ) {
        $self->logger->logdie( "ERROR: task not found: $tivoid" );
    };

    return $item_h;
}

sub lastupdate {
    my ( $self, $row, $date ) = @_;

    $row->{lastupdate} = $date;

    $self->sql->insert( 'lastupdate',
                        $row,
                        'tivo.lastupdate',
                    );

}

sub check_status {
    my ( $self, $item, $basedir, $library ) = @_;

    my $dir = lc( $item->{name} );
    $dir =~ s|[^\w\d\_\-\/]+|_|g;
    $dir =~ s|\_+|_|g;
    $dir =~ s|\_+$||g;

    my $filename_root;
    if ( $item->{episode} ) {
        $filename_root = lc( join( "_", $item->{name}, $item->{episode} ) );
    }
    else {
        $filename_root = lc( $item->{name} );
    }
    $filename_root =~ s|[^\w\d\_\-]+|_|g;
    $filename_root =~ s|\_+|_|g;
    $filename_root =~ s|\_\-\_|-|g;
    $filename_root =~ s|\_+$||g;

    my $filename = lc( join( "_", $filename_root, $item->{tivoid} ) );

    my $info;
    $info->{filename}  = $filename;
    $info->{directory} = $dir;
    $info->{tivo}      = "$dir/$filename.tivo";
    $info->{mpg}       = "$dir/$filename.mpg";

    my $update;

    my $min_size = $item->{size} * 1000000 * .7;

    if ( -r "$basedir/$info->{tivo}" ) {
        unless ( $item->{downloaded} ) {

            $update->{downloaded} = 1;
            $info->{downloaded} = 1;

            my $size = ( stat "$basedir/$info->{tivo}" )[7];

            unless ( $size > $min_size ) {
                $update->{errmsg} = ".tivo file is too small";
                $info->{errmsg} = ".tivo file is too small";
            }
        }

    }

    if ( -r "$basedir/$info->{mpg}" ) {

        my $size = ( stat "$basedir/$info->{mpg}" )[7];

        unless ( $item->{downloaded} ) {
            $update->{downloaded} = 1;
            $info->{downloaded} = 1;

            unless ( $size > $min_size ) {
                $update->{errmsg} = ".mpg file is too small";
                $info->{errmsg} = ".mpg file is too small";
            }
        }

        unless ( $item->{decoded} ) {
            $update->{decoded} = 1;
            $info->{decoded} = 1;

            unless ( $size > $min_size ) {
                $update->{errmsg} = ".mpg file is too small";
                $info->{errmsg} = ".mpg file is too small";
            }
        }
    }

    if ( $library && -d $library ) {

        my $glob;
        if ( $item->{episode} ) {
            $glob = "$library/$dir/$filename_root*";
        }
        else {
            $glob = "$library/$dir/$filename_root\_$item->{tivoid}*";
        }

        my @files = glob( $glob );
        if ( scalar @files ) {

            unless ( $item->{library} ) {
                $update->{library} = 1;
                $info->{library} = 1;
            }
        }
    }

    my $link = $item->{link};
    $link =~ s|\'|%27|g;

    unless ( $item->{curl_cmd} ) {
        unless ( $item->{tivo_key} ) {
            $self->logger->logdie( "ERROR: tivo_key not found" );
        }
        $update->{curl_cmd} =  "curl -S -s --digest -k -u 'tivo:$item->{tivo_key}' -c '$basedir/.cookies.txt' -o '$basedir/$info->{tivo}' '$link'",
    }

    unless ( $item->{tivodecode_cmd} ) {
        unless ( $item->{tivo_key} ) {
            $self->logger->logdie( "ERROR: tivo_key not found" );
        }
        $update->{tivodecode_cmd} = "tivodecode -m '$item->{tivo_key}' -o '$basedir/$info->{mpg}' '$basedir/$info->{tivo}' && rm '$basedir/$info->{tivo}'";
    }

    unless ( $item->{directory} ) {
        $update->{directory} = "$basedir/$dir";
    }

    if ( scalar keys ( %{ $update } ) ) {
        $update->{tivoid} = $item->{tivoid};
        $self->update( $update );
    }

    return $info;
}

sub monitor {
    my ( $self ) = @_;

    my @items;

    # get a list of all items that are marked for download but not added to queue
    $self->sql->select( { tablename => 'recorded',
                          where     => 'download = 1 AND ( enqueued IS NULL OR enqueued = "" )',
                          schema    => 'tivo.recorded',
                          callback  => sub {
                              my $item = shift;
                              push @items, $item;
                          },
                      } );

    for my $item ( @items ) {

        $self->logger->info( "Adding tivo commands to queue for $item->{name}" );

        # add command to download item from tivo
        $self->queue->enqueue( $item->{curl_cmd}, 'tivo',  "fetch $item->{name}" );

        # add command to convert .tivo to .mpg
        $self->queue->enqueue( $item->{tivodecode_cmd}, 'tivo', "decode $item->{name}" );

        $self->logger->info( "Checking directory: $item->{directory}" );
        unless( -d $item->{directory} ) {
            mkpath( $item->{directory} );
        }

        # mark this tivo item as enqueued
        $self->sql->update( 'recorded',
                            { enqueued => 1 },
                            { id => $item->{id} },
                            'tivo.recorded'
                        );
    }

    # call monitor_queue on the command queue object
    return $self->queue->monitor_queue( 'tivo' );
}


__PACKAGE__->meta->make_immutable;

1;

__END__

=back
