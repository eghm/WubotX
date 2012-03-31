package App::Wubot::Plugin::XMLTV;
use Moose;

# VERSION

use Date::Manip;

use App::Wubot::Logger;
use App::Wubot::SQLite;
use App::Wubot::Util::TimeLength;
use App::Wubot::Util::XMLTV;

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

has 'timelength' => ( is => 'ro',
                      isa => 'App::Wubot::Util::TimeLength',
                      lazy => 1,
                      default => sub {
                          return App::Wubot::Util::TimeLength->new();
                      },
                  );

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};
    my $config = $inputs->{config};

    my $xmlfile = $config->{xmlfile};

    my $sqlite = App::Wubot::SQLite->new( { file => $config->{dbfile} } );

    unless ( $config->{nofork} ) {
        my $pid = fork();
        if ( $pid ) {
            # parent process
            return { cache => { pid => $pid },
                     react => { subject => "launched xmltv child pid: $pid" }
                 };
        }
    }

    my $count = 0;

    # perform the check, catch any exceptions
    eval {                          # try

        $self->logger->warn( "Downloading and parsing XMLTV Data" );

        my $tv = App::Wubot::Util::XMLTV->new();
        $count = $tv->fetch_process_data( $xmlfile );

        $self->logger->warn( "Finished parsing XMLTV Data" );

        1;
    } or do {                   # catch

        $self->logger->error( "ERROR processing XMLTV Data: $@" );
        $self->reactor->( { subject => "Error processing XMLTV Data: $@" }, $config );

    };

    $self->reactor->( { subject => "Finished processing XMLTV Data: $count entries" }, $config );
    exit 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::XMLTV - fetch data from XMLTV and store in the wubot tv db

=head1 DESCRIPTION

TODO: More to come...


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
