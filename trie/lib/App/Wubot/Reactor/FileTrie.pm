package App::Wubot::Reactor::FileTrie;
use Moose;

# VERSION

use File::Path;
use File::Trie;
use YAML::XS;

use App::Wubot::Logger;

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

has 'filetrie' => ( is => 'ro',
                    isa => 'File::Trie',
                    lazy => 1,
                    default => sub {
                        my $self = shift;
                        return File::Trie->new( { root => $self->directory, maxdepth => 8 } );
                    },
                );

has 'directory' => ( is => 'ro',
                     isa => 'Str',
                     lazy => 1,
                     default => sub {
                         my $directory = join( "/", $ENV{HOME}, "wubot", "triedb" );
                         #unless ( -d $directory ) { mkpath( $dir ) }
                         return $directory;
                     },
                 );

sub react {
    my ( $self, $message, $config ) = @_;

    $self->filetrie->write( $message, $message->{checksum} );

    return $message;
}

__PACKAGE__->meta->make_immutable;

1;

__END__


=head1 NAME

App::Wubot::Reactor::FileTrie - store entire messages serialized using File::Trie


=head1 SYNOPSIS

  - name: store entire message using File::Trie
    plugin: FielTrie

=head1 DESCRIPTION

This plugin stores each message in a separate file under
~/wubot/triedb.  The filename for each message will come from the
message checksum.  To prevent too many messages from being stored in a
single subdirectory, the message is stored using File::Trie.

=head1 SUBROUTINES/METHODS

=over 8

=item react( $message, $config )

The standard reactor plugin react() method.

=back
