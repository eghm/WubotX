package App::Wubot::Plugin::Uptime;
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

sub validate_config {
    my ( $self, $config ) = @_;

    my @required_params = qw( command warning_load critical_load );

    for my $param ( @required_params ) {
        unless ( $config->{$param} ) {
            die "ERROR: required config param $param not defined for: ", $self->key, "\n";
        }
    }

    return 1;
}


sub check {
    my ( $self, $inputs ) = @_;

    $self->logger->debug( "Check command: $inputs->{config}->{command}" );

    my $uptime_output = `$inputs->{config}->{command}`;
    chomp $uptime_output;

    my ( $load01, $load05, $load15 ) = $self->_parse_uptime( $uptime_output );

    unless ( defined $load01 && defined $load05 && defined $load15 ) {
        $self->logger->logdie( "ERROR: unable to parse uptime output: $uptime_output" );
    }

    $self->logger->debug( "load: $load01 => $load05 => $load15" );

    my $subject;
    my $status = 'OK';
    if ( $inputs->{config}->{critical_load} && $load05 > $inputs->{config}->{critical_load} ) {
        $subject = "critical: load over last 5 minutes is $load01";
        $status = 'CRITICAL';
    } elsif ( $inputs->{config}->{warning_load} && $load05 > $inputs->{config}->{warning_load} ) {
        $subject = "warning: load over last 5 minute is $load05";
        $status = 'WARNING';
    }

    my $results = { load01  => $load01,
                    load05  => $load05,
                    load15  => $load15,
                    status  => $status,
                };

    if ( $subject ) {
        $results->{subject} = $subject;
    }

    return { react => $results };
}

sub _parse_uptime {
    my ( $self, $string ) = @_;

    unless ( $string =~ m/load averages?\: ([\d\.]+)\,?\s+([\d\.]+),?\s+([\d\.]+)/ ) {
        return;
    }

    my ( $load01, $load05, $load15 ) = ( $1, $2, $3 );

    return ( $load01, $load05, $load15 );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::Uptime - monitor system load

=head1 SYNOPSIS

  ~/wubot/config/plugins/Uptime/myhostname.yaml

  ---
  command: /usr/bin/uptime
  delay: 1m
  warning_load: 2.0
  critical_load: 3.0

=head1 DESCRIPTION

Monitors the system load by parsing the output of the 'uptime'
command.  For example, if the uptime command produced this output:

  12:06  up 4 days, 14:03, 15 users, load averages: 0.80 0.81 0.67

Then results will be sent in a message containing:

  load01: 0.80
  load05: 0.81
  load10: 0.67
  status: ok

The 'status' field will be set to 'ok' if the load is less than the
warning threshold, 'warning' if it is between the warning and critical
thresholds, or 'critical' if it is above the critical threshold.

If the 1-minute load value exceeds the warning_load or critical_load
threshold, then the message will contain a subject such as:

  warning: load over last 1 minute is {$load}
  critical: load over last 1 minute is {$load}


=head1 HINTS

This plugin can be used to monitor load on a remote system that is
accessible by ssh.  Simply set the command like so:

  ---
  command: ssh somehost /bin/uptime

=head1 EXAMPLE GRAPHS

  - http://www.geekfarm.org/wu/wubot/Uptime-navi-daily.png


=head1 SUBROUTINES/METHODS

=over 8

=item validate_config( $config )

The standard monitor validate_config() method.

=item check( $inputs )

The standard monitor check() method.

=back
