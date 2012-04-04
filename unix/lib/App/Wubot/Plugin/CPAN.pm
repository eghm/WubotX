package App::Wubot::Plugin::CPAN;
use Moose;

# VERSION

use App::Wubot::Logger;

has 'expire_age' => ( is => 'rw',
                      isa => 'Num',
                      default => sub { 60*60 },
                  );

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

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};
    my $config = $inputs->{config};

    # todo: forking plugin fu to prevent running more than one at once
    unless ( $config->{nofork} ) {
        my $pid = fork();
        if ( $pid ) {
            # parent process
            return { react => { subject  => "launched cpan child process: $pid",
                                coalesce => $self->key,
                            } }
        }
    }


    eval {                          # try

        my $perl = $config->{perl} || 'perl';

        my $command = "$perl -MCPAN -e 'CPAN::Shell->r'";

        my @react;

        # run command capturing output
        open my $run, "-|", "$command 2>&1" or die "Unable to execute $command: $!";

      MODULE:
        while ( my $line = <$run> ) {
            chomp $line;

            $self->logger->trace( $line );

            next unless $line =~ m|^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$|;

            my ( $module, $installed, $latest, $path ) = ( $1, $2, $3, $4 );

            next MODULE if $installed eq "undef" || ! $latest;

            #$self->logger->info( "Module needs update: $module: $installed => $latest" );

            my $cache_string = "$module:$latest";

            # if we've already seen this item, move along
            if ( $self->cache_is_seen( $cache, $cache_string ) ) {
                $self->logger->trace( "Already seen: ", $cache_string );

                # touch cache time on this subject
                $self->cache_mark_seen( $cache, $cache_string );

                next MODULE;
            }

            # keep track of this item so we don't fetch it again
            $self->cache_mark_seen( $cache, $cache_string );

            my $subject = "perl module out of date: $module: $installed => $latest";
            $self->logger->info( $subject );

            $self->reactor->( { subject   => $subject,
                                module    => $module,
                                installed => $installed,
                                lastest   => $latest,
                                path      => $path,
                                link      => "http://search.cpan.org/perldoc?$module",
                            },
                              $config
                          );
        }
        close $run;

        # check exit status
        unless ( $? eq 0 ) {
          my $status = $? >> 8;
          my $signal = $? & 127;

          $self->reactor->( { subject => "error running '$command': status=$status signal=$signal" }, $config );
        }

        # write out the updated cache
        $self->write_cache( $cache );

        1;
    } or do {                   # catch

        $self->logger->info( "ERROR: getting cpan module info: $@" );
    };

    exit 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::CPAN - verify that the latest versions of all Perl modules are installed


=head1 SYNOPSIS

  # The plugin configuration lives here:
  ~/wubot/config/plugins/CPAN/myhostname.yaml

  ---
  delay: 1d
  timeout: 300
  perl: /usr/local/bin/perl


=head1 DESCRIPTION

This plugin checks if there are any perl modules installed locally
which have a newer version available on CPAN.  The idea was stolen
from theory's nagios check:

  https://github.com/theory/check_perl_modules/blob/master/bin/check_perl_modules

I originally tried to steal the logic from the check_perl_modules
script, but the script makes a large number of calls (one for every
module installed) to a web service (cpanmetadb.appspot.com) which
overran its quota several times during my test.  So for the time
being, it uses the rather ugly approach of parsing the output of the
command:

  perl -MCPAN -e 'CPAN::Shell->r'

By default it will use the first 'perl' in the path, although you can
set the perl path (see the example above).  This makes it possible to
configure multiple monitors per host if there is more than one perl
installation you want to monitor.

To upgrade all the perl modules that have newer versions available,
use the command:

  perl -MCPAN -e 'CPAN::Shell->install(CPAN::Shell->r)'


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
