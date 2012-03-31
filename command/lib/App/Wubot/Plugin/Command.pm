package App::Wubot::Plugin::Command;
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

    my @required_params = qw( command );

    for my $param ( @required_params ) {
        unless ( $config->{$param} ) {
            die "ERROR: required config param $param not defined for: ", $self->key, "\n";
        }
    }

    return 1;
}


sub check {
    my ( $self, $inputs ) = @_;

    my $command = $inputs->{config}->{command};

    $self->logger->debug( $self->key, ": command: $command" );

    my $message;

    my $field = $inputs->{config}->{field} || "command_output";

    my @output;

    # run command capturing output
    open my $run, "-|", "$command 2>&1" or die "Unable to execute $command: $!";
    while ( my $line = <$run> ) {
      chomp $line;
      push @output, $line;
    }
    close $run;

    # check exit status
    if ( $? eq 0 ) {
        $message->{exit_status} = 0;
        $message->{signal}      = 0;
    }
    else {
        $message->{exit_status} = $? >> 8;
        $message->{signal}      = $? & 127;
    }

    my $output = join( "\n", @output );
    $self->logger->trace( "Output: $output" );

    $message->{ $field } = $output;

    return { react => $message };

}

__PACKAGE__->meta->make_immutable;

1;

__END__


=head1 NAME

App::Wubot::Plugin::Command - run an external command and capture the output and exit status

=head1

  ~/wubot/config/plugins/Command/netstat.yaml

  ---
  command: netstat -s
  delay: 1m


=head1 DESCRIPTION

This plugin is useful for running a command at regular intervals, and
then sending the output on to the reactor for further processing.

The output of the command will be sent in the field 'command_output'.

=head1 HINTS

Here is an example to parses the packages sent and received of the
output of 'netstat -s'.

    ---
    command: netstat -s
    delay: 1m

    react:

      - name: command regexp packets sent
        plugin: CaptureData
        config:
          source_field: command_output
          target_field: packets_sent
          regexp: '(\d+) packets sent'

      - name: command regexp packets received
        plugin: CaptureData
        config:
          source_field: command_output
          target_field: packets_received
          regexp: '(\d+) packets received'


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=item validate_config( $config )

The standard monitor validate_config() method.

=back
