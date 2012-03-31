package App::Wubot::Plugin::OsxActiveApp;
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

my $command =<<EOF;
/usr/bin/osascript -e 'tell application "System Events"' -e 'set frontApp to name of first application process whose frontmost is true' -e 'end tell'
EOF

sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    my $output = `$command`;

    chomp $output;

    return { react => { application => $output } };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Wubot::Plugin::OsxActiveApp - monitor current active application in OS X

=head1 SYNOPSIS

  ~/wubot/config/plugins/OsxActiveApp/navi.yaml

  ---
  enable: 1


=head1 DESCRIPTION

Runs a bit of applescript using the osascript command to determine
which application is currently active in OS X.

  /usr/bin/osascript -e 'tell application "System Events"' -e 'set frontApp to name of first application process whose frontmost is true' -e 'end tell'

Sends a message containing the field:

  application: {appname}


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
