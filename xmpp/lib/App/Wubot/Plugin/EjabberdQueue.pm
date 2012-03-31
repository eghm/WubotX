package App::Wubot::Plugin::EjabberdQueue;
use Moose;

# VERSION

use App::Wubot::Logger;
use App::Wubot::Util::WebFetcher;

with 'App::Wubot::Plugin::Roles::Cache';
with 'App::Wubot::Plugin::Roles::Plugin';

has 'fetcher' => ( is  => 'ro',
                   isa => 'App::Wubot::Util::WebFetcher',
                   lazy => 1,
                   default => sub {
                       return App::Wubot::Util::WebFetcher->new();
                   },
               );

sub check {
    my ( $self, $inputs ) = @_;

    my $config = $inputs->{config};
    my $cache  = $inputs->{cache};

    $self->logger->debug( "Fetching content from: $config->{url}" );

    my $content = $self->fetcher->fetch( $config->{url}, $config );

    my $users;
    while ( $content =~ m|\<tr\>\<td\>\<a href="..\/user\/.*?"\>(.*?)\<\/a\>\<\/td\>\<td\>\<a href="..\/user\/.*?"\>(\d+)\<\/a\>\<\/td\>|g ) {
        $users->{$1} = $2;
    }

    return { react => { users => $users }, cache => $cache };
}

__PACKAGE__->meta->make_immutable;

1;

__END__


=head1 NAME

App::Wubot::Plugin::EjabberdQueue


=head1 SYNOPSIS


=head1 SUBROUTINES/METHODS

=over 8

=item check( $inputs )

The standard monitor check() method.

=back
