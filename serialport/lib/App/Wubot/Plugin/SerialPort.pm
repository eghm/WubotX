package App::Wubot::Plugin::SerialPort;
use Moose;

# Set up the serial port
use Capture::Tiny;
use Device::SerialPort qw( :PARAM :STAT :ALL );

# VERSION

use App::Wubot::Logger;

has 'device'    => ( is      => 'rw',
                     isa     => 'Str',
                     default => '',
                 );

has 'port'      => ( is      => 'rw',
                     isa     => 'Maybe[Device::SerialPort]',
                 );

has 'logger'    => ( is      => 'ro',
                     isa     => 'Log::Log4perl::Logger',
                     lazy    => 1,
                     default => sub {
                         return Log::Log4perl::get_logger( __PACKAGE__ );
                     },
                 );

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

sub init {
    my ( $self, $inputs ) = @_;

    unless ( $inputs->{config}->{device} ) {
        $self->logger->logdie( "ERROR: 'device' not defined in config!" );
    }

    unless ( -r $inputs->{config}->{device} ) {
        $self->logger->logdie( "ERROR: device not readable: $inputs->{config}->{device}" );
    }

    $self->device( $inputs->{config}->{device} );

    return;
}

sub _initialize_serial_port {
    my ( $self ) = @_;

    $self->port( Device::SerialPort->new( $self->device ) );

    return unless $self->port;

    # 19200, 81N on the USB ftdi driver
    $self->port->baudrate(9600);
    $self->port->databits(8);
    $self->port->parity("none");
    $self->port->stopbits(1);

    # clear contents of port on startup
    $self->port->lookclear;
}

sub check {
    my ( $self, $inputs ) = @_;

    unless ( $self->port ) {
        $self->_initialize_serial_port();
    }

    my @react;
    my $string;

  READ:
    for ( 0 .. 10 ) {
        my ( $stdout, $stderr ) = Capture::Tiny::capture {
            # Poll to see if any data is coming in
            $string = $self->port->lookfor();
        };

        if ( $stderr =~ m|^Error| ) {
            push @react, { subject => "STDERR: $stderr" };
            $self->port( undef );
        }

        last READ unless $string;

        $string =~ s|\s$||;
        push @react, { line => $string, lastupdate => time };
    }

    return { react => \@react };

}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::SerialPort - monitor data received over a serial port

=head1 DESCRIPTION

More to come...


=head1 SUBROUTINES/METHODS

=over 8

=item init( $inputs )

The standard monitor init() method.

=item check( $inputs )

The standard monitor check() method.

=back
