package App::Wubot::Plugin::PathLastUpdate;
use Moose;

# VERSION

use App::Wubot::Logger;

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

use App::Wubot::Util::TimeLength;
my $timelength = App::Wubot::Util::TimeLength->new();

sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};
    my $config = $inputs->{config};

    my $path = $config->{path};

    unless ( -r $path ) {
        $self->logger->logdie( "path not found: $path" );
    }

    my $last_modified = ( stat $path )[9];

    my $age = time - $last_modified;

    my $seconds = $timelength->get_seconds( $config->{age} );

    if ( $age > $seconds ) {

        my $time_passed = $timelength->get_human_readable( $age );

        return { react => { subject => "path has not been updated in $time_passed", status => 'CRITICAL' } };
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__


=head1 NAME

App::Wubot::Plugin::PathLastUpdate - monitor the last modified time on a path


=head1 SYNOPSIS

  ~/wubot/config/plugins/PathLastUpdate/scifri.yaml

  ---
  path: /path/to/file
  age: 1w
  delay: 15m

=head1 DESCRIPTION

Monitor the last modified time on a file or directory and send a
notification if the last modified time is older than a configured
threshold.

If the path is not found, a message will be sent containing the
subject:

  path not found: {$path}

If the last modified date of the target path is older than the
specified age, then a message will be sent containing the subject:

  path has not been updated in {$time}

=head1 HINTS

I developed this monitor after being repeatedly aggravated that iTunes
will periodically stop updating a podcast if you do not regularly mark
items in the podcast as being seen.  This can be especially annoying
when podcasts don't always carry all the archived items!  Here is an
example config file I use to monitor the sci-fri directory to let me
know when the feed is not being updated:

  ---
  path: /Users/wu/Music/iTunes/iTunes Media/Podcasts/Science Friday Audio Podcast
  age: 1w1d
  delay: 15m


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
