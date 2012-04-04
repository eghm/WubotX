package App::Wubot::Reactor::MakeDirectory;
use Moose;

# VERSION

use File::Path;
use YAML::XS;

use App::Wubot::Logger;

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

sub react {
    my ( $self, $message, $config ) = @_;

    unless ( $config->{field} ) {
        $self->logger->error( "ERROR: MakeDirectory: field not defined in config", YAML::XS::Dump $config );
        return $message;
    }

    my $directory = $message->{ $config->{field} };

    unless ( $directory ) {
        $self->logger->error( "Could not create directory: $directory ( $config->{field} )" );
    }

    return $message if -d $directory;

    $self->logger->warn( "Creating directory: $directory" );

    eval {                          # try
        mkpath( $directory );
        1;
    } or do {                       # catch
        $self->logger->error( "Couldn't create directory: $directory: $@" );
    };

    return $message;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Reactor::MakeDirectory - create a subdirectory

=head1 DESCRIPTION

TODO: More to come...


=head1 SUBROUTINES/METHODS

=over 8

=item react( $message, $config )

The standard reactor plugin react() method.

=back
