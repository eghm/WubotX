package App::Wubot::Plugin::OsxBattery;
use Moose;

# VERSION

use App::Wubot::Logger;
use App::Wubot::Util::TimeLength;

has 'timelength' => ( is => 'ro',
                      isa => 'App::Wubot::Util::TimeLength',
                      lazy => 1,
                      default => sub {
                          return App::Wubot::Util::TimeLength->new();
                      },
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

my $command = "ioreg -l";

my $last_notification;

sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    my $percent;

    my ( $max, $current ) = @_;
    for my $line ( split /\n/, `$command` ) {

        next unless $line =~ m|Capacity|;

        if ( $line =~ m|MaxCapacity| ) {
            $line =~ m|\=\s+(\d+)|;
            $max = $1;
            $self->logger->debug( "MAX: $max" );
        }
        elsif ( $line =~ m|CurrentCapacity| ) {
            $line =~ m|\=\s+(\d+)|;
            $current = $1;
            $self->logger->debug( "CURRENT: $current" );
        }
    }

    my $results;

    $results->{percent} = sprintf( "%d", 100 * $current / $max );
    $results->{current} = $current;
    $results->{max}     = $max;
    $results->{subject} = "Battery at $results->{percent}%";

    return { cache => $cache, react => $results };
}

__PACKAGE__->meta->make_immutable;

1;

__END__


=head1 NAME

App::Wubot::Plugin::OsxBattery - monitor battery on OS X


=head1 SYNOPSIS

  ~/wubot/config/plugins/OsxBattery/myhost.yaml

  ---
  delay: 5m


=head1 DESCRIPTION



=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
