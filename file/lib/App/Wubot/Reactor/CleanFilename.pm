package App::Wubot::Reactor::CleanFilename;
use Moose;

# VERSION

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
        $self->logger->error( "ERROR: CleanFilename: field not defined in config", YAML::XS::Dump $config );
        return $message;
    }

    my $filename = $message->{ $config->{field} };

    unless ( $filename ) {
        $self->logger->error( "ERROR: CleanFilename: message field $config->{field} not defined" );
        return $message;
    }

    # anything that isn't a specifically allowed character is replaced
    # with an underscore
    if ( $config->{directory} ) {
        $filename =~ s|[^\w\d\_\-\.\/]+|_|g;
    }
    else {
        $filename =~ s|[^\w\d\_\-\.]+|_|g;
    }

    if ( $config->{lc} ) {
        $filename = lc( $filename );
    }

    # replace multiple underscores with a single underscore
    $filename =~ s|\_+|_|g;

    # other cleanup
    $filename =~ s|\_\-\_|-|g;

    $message->{ $config->{field} } = $filename;

    return $message;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Reactor::CleanFilename - build a clean filename or directory name from a field


=head1 SYNOPSIS

  - name: clean filename
    plugin: CleanFilename
    config:
      field: filename_base

  - name: clean filename
    plugin: CleanFilename
    config:
      field: directory
      directory: 1
      lc: 1


=head1 DESCRIPTION

This plugin will take the contents of a field and make it into a safe
filename.  This includes replacing any characters other than the
following with underscores:

  a-z, A-Z, 0-9
  _ (underscore)
  - (dash)
  . (period)

If the 'directory' config param is set, then a forward slash will also
be allowed in the name.  This can be useful with the MakeDirectory
plugin.

Setting the 'lc' config param will lower-case the contents.

Some additional cleanup is done to make the filename pretty:

  multiple consecutive underscores are replaced with a single underscore
  _-_ will be replaced with simply -
  "foo's thing" will become "foos_thing" rather than "foo_s_thing"

=head1 SUBROUTINES/METHODS

=over 8

=item react( $message, $config )

The standard reactor plugin react() method.

=back
