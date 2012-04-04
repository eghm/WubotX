package App::Wubot::Plugin::DiskSpace;
use Moose;

# VERSION

use App::Wubot::Logger;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

sub validate_config {
    my ( $self, $config ) = @_;

    my @required_params = qw( command critical_percent warning_percent );

    for my $param ( @required_params ) {
        unless ( $config->{$param} ) {
            die "ERROR: required config param $param not defined for: ", $self->key, "\n";
        }
    }

    return 1;
}

sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};
    my $config = $inputs->{config};

    my @react;

  LINE:
    for my $line ( split /\n/, `$config->{command} 2>/dev/null` ) {

        # skip header line
        next if $line =~ m|^Filesystem\s+|;
        next if $line =~ m|Permission denied|;

        next unless $line =~ m|\s(\d+)\%\s*(.*)$|;
        my ( $percent, $mount ) = ( $1, $2, $3 );

        # skip-able filesystems
        for my $skip ( keys %{ $config->{skip} } ) {
            next LINE if $mount =~ m|$skip|;
        }

        # only trigger a reaction when the percent changes
        next if $cache->{ $mount } && $cache->{ $mount } == $percent;

        # update the cache
        $cache->{ $mount } = $percent;

        my $subject = "";
        my $status = "ok";
        if ( $percent > $config->{critical_percent} ) {
            $subject = "critical: disk use on $mount is $percent";
            $status = 'critical';
        } elsif ( $percent > $config->{warning_percent} ) {
            $subject = "warning: disk use on $mount is $percent";
            $status = 'warning';
        }

        push @react, { filesystem => $mount,
                       percent    => $percent,
                       status     => $status,
                       subject    => $subject,
                   };

    }

    return { cache => $cache, react => \@react };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::DiskSpace - monitor disk space

=head1 SYNOPSIS

  ~/wubot/config/plugins/DiskSpace/myhostname.yaml

  ---
  command: df -k
  critical_percent: 95
  warning_percent: 90
  skip:
    '/dev': 1
  delay: 15m

=head1 DESCRIPTION

Monitors disk space by parsing the output of 'df -k'.

For each mounted filesystem that is not matched by one of the 'skip'
entries, a message will be sent containing:

  filesystem: /mount/point
  percent: percent used

The message will also contain a 'status' field that will be set to
'ok' if the percent utilization is less than the warning threshold,
'warning' if it is between the warning and critical thresholds, or
'critical' if it is above the critical threshold.

If the filesystem's percent utilization exceeds the warning_percent or
critical_percent, then the message will contain a subject such as:

  warning: disk use on /mount/point is 93%
  critical: disk use on /mount/point is 99%


=head1 HINTS

This plugin can be used to monitor disk space on a remote system that
is accessible by ssh.  Simply set the command like so:

  ---
  command: ssh somehost df -k


=head1 SUBROUTINES/METHODS

=over 8

=item validate_config( $config )

The standard monitor validate_config() method.

=item check( $inputs )

The standard monitor check() method.

=back
