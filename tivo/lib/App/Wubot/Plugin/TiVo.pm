package App::Wubot::Plugin::TiVo;
use Moose;

# VERSION

use Net::TiVo;

use App::Wubot::Logger;
use App::Wubot::Util::Tivo;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

has 'reactor'  => ( is => 'ro',
                    isa => 'CodeRef',
                    required => 1,
                );

has 'logger'  => ( is => 'ro',
                   isa => 'Log::Log4perl::Logger',
                   lazy => 1,
                   default => sub {
                       return Log::Log4perl::get_logger( __PACKAGE__ );
                   },
               );

has 'sql'    => ( is      => 'ro',
                  isa     => 'App::Wubot::SQLite',
                  lazy    => 1,
                  default => sub {
                      return App::Wubot::SQLite->new( { file => $_[0]->dbfile } );
                  },
              );

has 'dbfile' => ( is      => 'rw',
                  isa     => 'Str',
                  lazy    => 1,
                  default => sub {
                      return join( "/", $ENV{HOME}, "wubot", "sqlite", "tivo.sql" );
                  },
              );

has 'tivo'   => ( is      => 'rw',
                  isa     => 'App::Wubot::Util::Tivo',
                  lazy    => 1,
                  default => sub {
                      return App::Wubot::Util::Tivo->new();
                  }
              );


sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};
    my $config = $inputs->{config};

    my $now = time;

    eval {
        my @results = $self->tivo->monitor( 'tivo' );

        # if we got queue results, return them now
        if ( scalar @results ) {
            return { cache => $cache, react => \@results };
        }
    };

    # only fetch new data every 4 hours
    my $lastupdate = $cache->{last_fetch} || 0;
    my $age = time - $lastupdate;
    return if $age < 3600;
    $cache->{last_fetch} = time;

    # todo: forking plugin fu to prevent running more than one at once
    unless ( $config->{nofork} ) {
        my $pid = fork();
        if ( $pid ) {
            # parent process
            return { react => { info     => "launched tivo child process: $pid",
                                pid      => $pid,
                                coalesce => $self->key,
                            } }
        }
    }

    eval {                          # try

        my $tivo = Net::TiVo->new(
            host  => $config->{host},
            mac   => $config->{key},
        );

        my $folder_count;
        my $show_count;
        my $total_size;
        my $new_size;

      FOLDER:
        for my $folder ($tivo->folders()) {

            $folder_count++;

            my $folder_string = $folder->as_string();
            $self->logger->debug( "TIVO FOLDER: $folder_string" );

            next if $folder_string =~ m|^HD Recordings|;

          SHOW:
            for my $show ($folder->shows()) {

                $show_count++;

                # size in MB
                my $size     = int( $show->size() / 1000000 );
                $total_size += $size;

                my $show_string = $show->as_string();

                next SHOW if $show->in_progress();

                $new_size += $size;

                my $subject = join ": ", $show->name(), $show->episode();

                # duration in minutes
                my $duration = int( $show->duration() / 60000 );

                my $item = { subject     => $subject,
                             name        => $show->name(),
                             episode     => $show->episode(),
                             episode_num => $show->episode_num(),
                             recorded    => $show->capture_date(),
                             format      => $show->format(),
                             hd          => $show->high_definition(),
                             size        => $size,
                             channel     => $show->channel(),
                             duration    => $duration,
                             description => $show->description(),
                             program_id  => $show->program_id(),
                             series_id   => $show->series_id(),
                             link        => $show->url(),
                             coalesce    => $self->key,
                             lastupdate  => $now,
                             tivo_key    => $config->{key},
                         };

                # get the unique tivo recording id
                $item->{link} =~ m/\=(\d+)$/;
                $item->{tivoid} = $1;

                # insert/update data in the tivo sqlite db
                $self->tivo->update( $item );

                # check if the file has been downloaded
                $self->tivo->check_status( $item, $config->{directory}, $config->{library} );

                # only send the reaction when the show is new
                unless ( $cache->{shows}->{$show_string} ) {
                    $self->reactor->( $item,
                                      $config
                                  );
                }

                $cache->{shows}->{$show_string} = 1;
            }
        }

        unless ( $show_count ) {
            $self->logger->logdie( "ERROR: now show information retrieved from the tivo" );
        }

        my $message = { shows      => $show_count,
                        folders    => $folder_count,
                        size       => $total_size,
                        new_size   => $new_size,
                    };

        if ( $config->{hd} ) {
            my $percent = int( $total_size / $config->{hd} ) / 10;
            $message->{percent} = $percent;
            $message->{subject} = "Totals: $percent% shows=$show_count folders=$folder_count new=$new_size total=$total_size",
        }
        else {
            $message->{subject} = "Totals: shows=$show_count folders=$folder_count new=$new_size total=$total_size",
        }

        $self->reactor->( $message, $config );

        # write out the updated cache
        $cache->{lastupdate} = time;
        $self->write_cache( $cache );

        $self->tivo->lastupdate( $message, $now );

        1;
    } or do {                   # catch
        my $error = "ERROR: getting tivo info: $@";

        $self->reactor->( { subject => $error,
                            status  => 'CRITICAL',
                        },
                          $config
                      );

        $self->logger->fatal( $error );
    };

    exit 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::TiVo - monitor a tivo for new recordings


=head1 SYNOPSIS

  ~/wubot/config/plugins/TiVo/hd.yaml

  ---
  delay: 8h
  host: 192.168.1.123
  key: 0123456789
  hd: 600

=head1 DESCRIPTION

This monitor uses L<Net::TiVo> to fetch the 'Now Playing' list from
your tivo.  For each new item that shows up in the list, a message is
sent containing the following fields:

  subject: {name}: {episode}
  name: show name
  episode: episode name
  episode_num: episode number
  recorded: capture date
  format: file format
  hd: {high-def flag}
  size: recording size
  channel: recorded channel
  duration: length
  description: program description
  program_id: tivo program id
  series_id: tivo series id
  link: link to download program from tivo

For more information on these fields, see L<Net::TiVo>.

In addition to a message being sent for each recorded item, a message
will be sent containing information about the totals:

  subject: Totals: shows=$show_count folders=$folder_count new=$new_size total=$new_size
  shows: number of recorded items
  folders: number of folders
  size: total megabytes used
  new_size: size of new found programs
  percent: percentage of drive utilized

The 'percent' field will only show up if you have the hard drive size
in your configuration (the 'hd' param).  If that is the case, then the
percent utilized will also show up in the title.




=head1 SQLITE

If you want to store your TiVo programs in a SQLite database, you can
do so with the following reaction:

  - name: tivo
    condition: key matches ^TiVo
    rules:
      - name: tivo sqlite
        plugin: SQLite
        config:
          file: /usr/home/wu/wubot/sqlite/tivo.sql
          tablename: recorded

The 'recorded' schema should be copied from the wubot tarball in the
config/schema/ directory into your ~/wubot/schemas.

=head1 DOWNLOADING TIVO PROGRAMS

TiVo programs can be downloaded from the link specified in the
message.  It is possible to use wubot to fully automate this process,
although that is not yet documented.

You can download a program manually by using a curl command such as:

  curl --digest -k -u tivo:{media_key} -c cookies.txt -o {some_filename}.tivo '{url}'

Note that some programs (e.g. those that are downloaded from the web)
may be protected, and can not be downloaded.


=head1 TIVO KEY

You absolutely must specify your media key in the 'key' field of the
config or you won't be able to get any information from your TiVo.


=head1 CERTIFICATE

The certificate on your TiVo is self-signed, so if you try to fetch
the content, it will give you a certificate error.  Adding this
certificate to the list of accepted certificates on your system is
beyond the scope of this document.

If you are unable to authorize the certificate on your operating
system, you can retrieve the cert by doing something like this:

  openssl openssl s_client -showcerts -connect 192.168.1.140:443

Capture each of the certs with the lines containing BEGIN CERTIFICATE
through END CERTIFICATE and put them in a file such as:

  ~/wubot/ca-bundle

Then when starting wubot-monitor, set the environment variable
HTTPS_CA_FILE to point at your ca-bundle:

  HTTPS_CA_FILE=~/wubot/ca-bundle wubot-monitor -v


=head1 CACHE

This monitor uses the global cache mechanism, so each time the check
runs, it will update a file such as:

  ~/wubot/cache/TiVo-hd.yaml

The monitor caches all shows in the feed in this file.  When a new
(previously unseen) program shows up on the feed, the message will be
sent, and the cache will be updated.  Removing the cache file will
cause all matching items to be sent again.


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
