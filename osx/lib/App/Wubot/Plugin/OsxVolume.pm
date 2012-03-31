package App::Wubot::Plugin::OsxVolume;
use Moose;

# VERSION

use App::Wubot::Logger;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

sub check {
    my ( $self, $inputs ) = @_;

    my $cache  = $inputs->{cache};
    my $config = $inputs->{config};

    my $settings;

    for my $setting ( split /\, /, `osascript -e 'get volume settings'` ) {

        $setting =~ m|^(.*)\:(.*)$|;

        $settings->{ $1 } = $2;
    }

    if ( $config->{alert_muted} && $settings->{'output muted'} eq "true" ) {
        return { react => { subject => 'volume muted', status => 'WARNING' } };
    }

    if ( $settings->{'output volume'} < $config->{min_volume} ) {
        return { react => { subject => "low volume: $settings->{'output volume'}", status => 'WARNING' } };
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__


=head1 NAME

App::Wubot::Plugin::OsxVolume - monitor OS X volume


=head1 SYNOPSIS

  ~/wubot/config/plugins/OsxVolume/navi.yaml

  ---
  min_volume: 26
  alert_muted: 1
  delay: 300


=head1 DESCRIPTION

Monitor the volume on OS X by parsing the output of:

  osascript -e 'get volume settings'

If the volume is below a configured threshold, or optionally if it is
muted, wubot will send a message with a subject that indicates one of
the following:

  volume muted
  low volume: {$volume}

=head1 HINTS

When using voice notifications from wubot, it may sometimes be
necessary to mute or lower the volume.  This monitor can alert you
when you have accidentally left the volume too low so and thus may not
be able to hear voice notifications.


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
