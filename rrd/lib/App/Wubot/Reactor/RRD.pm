package App::Wubot::Reactor::RRD;
use Moose;

# VERSION

use Capture::Tiny;
use File::Path;
use POSIX qw(strftime);
use RRD::Simple;
use RRDs;
use YAML::XS;

use App::Wubot::Logger;

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

has 'lastupdates'  => ( is => 'ro',
                        isa => 'HashRef',
                        lazy => 1,
                        default => sub {
                            return {};
                        },
                    );

my $version = $RRDs::VERSION;

my $option_versions = { 'right-axis' => 1.2029,
                    };



sub react {
    my ( $self, $message, $config ) = @_;

    unless ( $config->{fields} ) {
        $self->logger->logdie( "RRD reaction called missing required config param: fields" );
    }

    my $time = $message->{lastupdate} || time;

    my $key;
    if ( $config->{key_field} ) {
        my @keys;
        for my $field ( split /\s+/, $config->{key_field} ) {
            push @keys, $message->{ $field };
        }
        $key = join( "-", @keys );
    }
    else {
        $key = $message->{key};
     }

    my $rrd_dir      = join( "/", $config->{base_dir}, "rrd", $key );
    unless ( -d $rrd_dir ) {
        mkpath( $rrd_dir );
    }

    my $graph_dir = join( "/", $config->{base_dir}, "graphs", $key );
    unless ( -d $graph_dir ) {
        mkpath( $graph_dir );
    }

    my %rrd_data;
    for my $field ( sort keys %{ $config->{fields} } ) {
        $rrd_data{$field} = $message->{$field};
    }

    my $filename = $config->{filename} || $key || 'data';
    my $rrd_filename = join( "/", $rrd_dir, "$filename.rrd" );

    my $rrd = RRD::Simple->new( file => $rrd_filename );

    unless ( -r $rrd_filename ) {
        $self->logger->warn( "Creating RRD filename: $rrd_filename" );

        $rrd->create( %{ $config->{fields} } );
    }

    # if rrd heartbeat configured, ensure the heartbeat is set on all data sources
    if ( $config->{heartbeat} ) {
        for my $field ( sort keys %{ $config->{fields} } ) {
            unless ( $config->{heartbeat} == $rrd->heartbeat( $rrd_filename, $field ) ) {
                $rrd->heartbeat( $rrd_filename, $field, $config->{heartbeat} );
            }
        }
    }

    if ( $config->{debug} ) {
        print YAML::XS::Dump { key => $key, rrd => \%rrd_data };
    }

    if ( $self->lastupdates->{$rrd_filename} && $self->lastupdates->{$rrd_filename} == $time ) {
        $self->logger->warn( "ERROR: tried to update $rrd_filename again in the same second" );
    }
    else {
        $rrd->update( $rrd_filename, $time, %rrd_data );
        $self->lastupdates->{$rrd_filename} = $time;
    }

    # log the value
    if ( $config->{log} ) {
        open(my $fh, ">>", $config->{log})
                or die "Couldn't open $config->{log} for writing: $!\n";

        for my $field ( keys %rrd_data ) {
            print $fh join( ", ", scalar localtime( $time ), $field, $rrd_data{$field} ), "\n";
        }

        close $fh or die "Error closing file: $!\n";
    }

    # if this message is more than 5 minutes old, don't generate the
    # graphs.  this prevents regenerating the same graphs over and
    # over when the queue is behind
    return $message if $message->{lastupdate} && time - $message->{lastupdate} > 300;

    # graph
    my $period = $config->{period} || [ 'day' ];

    $self->logger->debug( "Regenerating rrd graph: $graph_dir" );

    my %graph_options = ( destination => $graph_dir,
                          periods     => $period,
                          color       => $config->{color} || [ 'BACK#666666', 'CANVAS#111111' ],
                      );

    if ( $config->{graph_options} ) {

      OPTION:
        for my $option ( keys %{ $config->{graph_options} } ) {

            if ( $option_versions->{ $option } ) {
                unless ( $version >= $option_versions->{$option} ) {
                    $self->logger->debug( "Disabling $option on older version of rrdtool, requires $option_versions->{$option}" );
                    next OPTION;
                }
            }

            $graph_options{ $option } = $config->{graph_options}->{ $option };
        }
    }

    my ( $stdout, $stderr ) = Capture::Tiny::capture {
        my %rtn = $rrd->graph( %graph_options );
    };

    return $message;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Reactor::RRD - store data in an RRD with RRD::Simple

=head1 SYNOPSIS

  - name: rrd
    plugin: RRD
    config:
      base_dir: /home/wu/wubot/rrd
      fields:
        packets_sent: COUNTER
        packets_received: COUNTER
      period:
        - day
        - week
        - month
      graph_options:
        right-axis: 1:0
        width: 375


=head1 DESCRIPTION

TODO: More to come...


=head1 SUBROUTINES/METHODS

=over 8

=item react( $message, $config )

The standard reactor plugin react() method.

=back
