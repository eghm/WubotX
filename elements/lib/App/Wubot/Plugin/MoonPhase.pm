package App::Wubot::Plugin::MoonPhase;
use Moose;

# VERSION

use Astro::MoonPhase;

use App::Wubot::Logger;
use App::Wubot::Util::TimeLength;

has 'timelength' => ( is => 'ro',
                      isa => 'App::Wubot::Util::TimeLength',
                      lazy => 1,
                      default => sub { return App::Wubot::Util::TimeLength->new(); },
                  );

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

sub check {
    my ( $self, $inputs ) = @_;

    my $now = time;

    my ( $MoonPhase,
         $MoonIllum,
         $MoonAge,
         $MoonDist,
         $MoonAng,
         $SunDist,
         $SunAng    ) = phase( $now );

    my $message = { phase      => $MoonPhase,
                    illum      => $MoonIllum,
                    age        => $MoonAge,
                    moon_dist  => $MoonDist,
                    ang        => $MoonAng,
                    sun_dist   => $SunDist,
                    sun_ang    => $SunAng,
                };

    my @phases = phasehunt( $now );

    my $phases = { last_new_moon => $phases[0],
                   full_moon     => $phases[2],
                   new_moon      => $phases[4],
               };

    my $next_phase;
    for my $phase ( keys %{ $phases } ) {
        $message->{phases}->{$phase}->{until} = int( $phases->{ $phase } - $now );
        next if $phases->{ $phase } < $now;
        next if $next_phase && $phases->{$phase} > $phases->{$next_phase};
        $next_phase = $phase;
    }

    my $next_until = $self->timelength->get_human_readable( $message->{phases}->{$next_phase}->{until} );
    $message->{subject} = "$next_until until $next_phase";

    return { react => $message, cache => $message };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::MoonPhase - monitor the phase of the moon


=head1 SYNOPSIS

  ~/wubot/config/plugins/MoonPhase/home.yaml

  ---
  delay: 24h


=head1 DESCRIPTION

Reports the amount of time remaining until the next full or new moon,
whichever is closer.


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
