package App::Wubot::Plugin::Directory;
use Moose;

# VERSION

use App::Wubot::Logger;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    my $directory = $config->{path};

    unless ( -d $directory ) {
        $self->logger->logdie( "Error: directory not found: $directory" );
    }

    my @react;

    my $dir_h;
    opendir( $dir_h, $directory ) or die "Can't opendir $directory: $!";

  ENTRY:
    while ( defined( my $entry = readdir( $dir_h ) ) ) {

        next unless $entry;
        if ( $entry eq "." || $entry eq ".." ) { next }

        # if we've already seen this item, move along
        if ( $self->cache_is_seen( $cache, $entry ) ) {
            $self->logger->trace( "Already seen: ", $entry );

            # touch cache time on this subject
            $self->cache_mark_seen( $cache, $entry );

            next ENTRY;
        }

        # this item is still in the directory
        $self->cache_mark_seen( $cache, $entry );

        push @react, { file => $entry, subject => "New: $entry" };

    }

    $self->cache_expire( $cache );

    return { cache => $cache, react => \@react };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::Directory - monitor a directory for new files

=head1 SYNOPSIS

  ~/wubot/config/plugins/Directory/scifri.yaml

  ---
  path: /Users/wu/Music/iTunes/iTunes Media/Podcasts/Science Friday Audio Podcast
  delay: 15m


=head1 DESCRIPTION

This plugin monitors a directory for newly added files.  When a new
file is found, the message sent will contain the fields:

  file: {filename}
  subject: New: {filename}


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
