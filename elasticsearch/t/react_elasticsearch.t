#!/perl
use strict;
use warnings;

use Capture::Tiny qw/capture/;
use ElasticSearch;
use File::Temp qw/ tempdir /;
use Test::More;
use Test::Routine;
use Test::Routine::Util;
use YAML;

use App::Wubot::Logger;
use App::Wubot::Reactor::ElasticSearch;

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

has reactor => (
    is   => 'ro',
    lazy => 1,
    clearer => 'reset_reactor',
    default => sub {
        App::Wubot::Reactor::ElasticSearch->new();
    },
);

has 'es' => ( is => 'ro',
              isa => 'ElasticSearch',
              default => sub {
                  return ElasticSearch->new();
              },
          );


test "test reactor" => sub {
    my ($self) = @_;

    $self->reset_reactor;

    is_deeply( $self->reactor->react( {}, {} ),
               {},
               "Empty message results in no reaction field"
           );

};

test "errors" => sub {
    my ($self) = @_;

    $self->reset_reactor;

    {
        my $message = { subject => 'foo' };

        my ($stdout, $stderr) = capture {
            $self->reactor->react( $message, {} );
        };

        like( $stderr,
              qr/'id_field' not found in config/,
              "Checking id_field not found in config"
          );
    }

    {
        my $message = { subject => 'foo' };

        my ($stdout, $stderr) = capture {
            $self->reactor->react( $message, { id_field => 'id' } );
        };

        like( $stderr,
              qr/'id_field' id not found in message/,
              "Checking id_field not found in message"
          );
    }

    {
        my $message = { subject => 'foo', id => 'testme' };

        my ($stdout, $stderr) = capture {
            $self->reactor->react( $message, { id_field => 'id' } );
        };

        like( $stderr,
              qr/'type' not found in config/,
              "Checking type not found in config"
          );
    }

    {
        my $message = { subject => 'foo', id => 'testme' };

        my ($stdout, $stderr) = capture {
            $self->reactor->react( $message, { id_field => 'id', type => 'testcase' } );
        };

        like( $stderr,
              qr/'index_field' not found in config/,
              "Checking index_field not found in config"
          );
    }

    {
        my $message = { subject => 'foo', id => 'testme' };

        my ($stdout, $stderr) = capture {
            $self->reactor->react( $message, { id_field => 'id', type => 'testcase', index_field => 'foo' } );
        };

        like( $stderr,
              qr/'index_field' foo not found in message/,
              "Checking index_field not found in message"
          );
    }
};


test "simple insert" => sub {
    my ($self) = @_;

    $self->reset_reactor;

    my $message = { subject => 'test case subject', message_id => 'test-1', key => 'testkey' };

    is_deeply( $self->reactor->react( $message,
                                      { id_field    => 'message_id',
                                        type        => 'test',
                                        index_field => 'key',
                                    } ),
               $message,
               "inserting test message"
           );

    my $got = $self->es->get( index   => 'testkey',
                               type    => 'test',
                               id      => 'test-1'
                           );

    is_deeply( $got->{_source},
               $message,
               "Getting message out of ElasticSearch"
           );

    $self->es->delete( index => 'testkey', type => 'test', id => 'test-1' );
};


run_me;
done_testing;
