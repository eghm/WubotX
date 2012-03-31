#!/perl
use strict;
use warnings;

use Test::More;
use Test::Routine;
use Test::Routine::Util;

use File::Temp qw/ tempdir /;
use YAML;

BEGIN {
    if ( $ENV{HARNESS_ACTIVE} ) {
        $ENV{WUBOT_SCHEMAS} = "config/schemas";
    }
}

use App::Wubot::Logger;
use App::Wubot::Util::TagPredict;

has util => (
    is   => 'ro',
    lazy => 1,
    clearer => 'reset_util',
    default => sub {
        my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );
        App::Wubot::Util::TagPredict->new( dbfile => "$tempdir/test.db" );
    },
);

test "count_words" => sub {
    my ($self) = @_;

    is_deeply( $self->util->count_words( 'aaa aba aaa abb abc aaa' ),
               { aaa => 3,
                 aba => 1,
                 abb => 1,
                 abc => 1,
                 _TOTAL_ => 6,
             },
               "Counting word frequency of a simple string"
           );

    is_deeply( $self->util->count_words( 'aaa ab1 aaa ab1' ),
               { aaa => 2,
                 ab1 => 2,
                 _TOTAL_ => 4,
             },
               "Counting word frequency with some words containing numbers"
           );

    is_deeply( $self->util->count_words( 'Aaa aaa' ),
               { aaa => 2,
                 _TOTAL_ => 2,
             },
               "Counting word frequency with some words in different cases"
           );

    is_deeply( $self->util->count_words( 'Aaa; aa-a a.a.a' ),
               { aaa => 3,
                 _TOTAL_ => 3,
             },
               "Counting word frequency with some words containing special characters"
           );

    is_deeply( $self->util->count_words( 'aaa aaa', 'aaa' ),
               { aaa => 3,
                 _TOTAL_ => 3,
             },
               "Counting word frequency for multiple strings"
           );

};

test "count_words with skip words" => sub {
    my ($self) = @_;

    is_deeply( $self->util->count_words( 'now is the time' ),
               { now  => 1,
                 time => 1,
                 _TOTAL_ => 2,
             },
               "Counting word frequency skips words the 'the' and 'is'"
           );

    is_deeply( $self->util->count_words( 'now 1 12 123' ),
               { now  => 1,
                 123  => 1,
                 _TOTAL_ => 2,
             },
               "Counting word frequency skips single and double-digit numbers"
           );
};

test 'store documents with one tag' => sub {
    my $self = shift;

    $self->reset_util;

    ok( $self->util->store( { aaa => 1, bbb => 2, _TOTAL_ => 3 }, 'foo' ),
        "Storing words for 'foo' tag"
    );

    is( $self->util->db->{"count_tag_doc:foo"},
        1,
        "Checking that 'foo' has 1 doc"
    );

    is( $self->util->db->{"count_tag_doc:_TOTAL_"},
        1,
        "Checking that '_TOTAL_' has 1 doc"
    );

    is( $self->util->db->{"count_tag_word:foo:aaa"},
        1,
        "Checking that 'foo' has 1 word 'aaa'"
    );

    is( $self->util->db->{"count_tag_word:_TOTAL_:aaa"},
        1,
        "Checking that '_TOTAL_' has 1 word 'aaa'"
    );

    is( $self->util->db->{"count_tag_word:foo:bbb"},
        2,
        "Checking that 'foo' has 2 words 'bbb'"
    );

    is( $self->util->db->{"count_tag_word:_TOTAL_:bbb"},
        2,
        "Checking that '_TOTAL_' has 2 words 'bbb'"
    );

    is( $self->util->db->{"unique_word_count:aaa"},
        1,
        "Checking that there is one document containing 'aaa'"
    );

    is( $self->util->db->{"unique_word_count:bbb"},
        1,
        "Checking that there is one document containing 'bbb'"
    );

    is( $self->util->db->{"unique_word_count:_TOTAL_"},
        2,
        "Checking that there are 2 unique words in dictionary"
    );
};

test 'store documents with two tags' => sub {
    my $self = shift;

    $self->reset_util;

    ok( $self->util->store( { aaa => 1, bbb => 2, _TOTAL_ => 3 }, 'foo', 'bar' ),
        "Storing words for 'foo' and 'bar' tags"
    );

    is( $self->util->db->{"count_tag_doc:foo"},
        1,
        "Checking that 'foo' has 1 doc"
    );

    is( $self->util->db->{"count_tag_doc:bar"},
        1,
        "Checking that 'bar' has 1 doc"
    );

    is( $self->util->db->{"count_tag_doc:_TOTAL_"},
        1,
        "Checking that '_TOTAL_' has 1 doc"
    );

    is( $self->util->db->{"count_tag_word:foo:aaa"},
        1,
        "Checking that 'foo' has 1 word 'aaa'"
    );

    is( $self->util->db->{"count_tag_word:bar:aaa"},
        1,
        "Checking that 'bar' has 1 word 'aaa'"
    );

    is( $self->util->db->{"count_tag_word:_TOTAL_:aaa"},
        1,
        "Checking that '_TOTAL_' has 1 word 'aaa'"
    );

    is( $self->util->db->{"count_tag_word:foo:bbb"},
        2,
        "Checking that 'foo' has 2 words 'bbb'"
    );

    is( $self->util->db->{"count_tag_word:bar:bbb"},
        2,
        "Checking that 'bar' has 2 words 'bbb'"
    );

    is( $self->util->db->{"count_tag_word:_TOTAL_:bbb"},
        2,
        "Checking that '_TOTAL_' has 2 words 'bbb'"
    );

    is( $self->util->db->{"unique_word_count:aaa"},
        1,
        "Checking that there is one document containing 'aaa'"
    );

    is( $self->util->db->{"unique_word_count:bbb"},
        1,
        "Checking that there is one document containing 'bbb'"
    );

    is( $self->util->db->{"unique_word_count:_TOTAL_"},
        2,
        "Checking that there are 2 unique words in dictionary"
    );
};

test 'tag list' => sub {
    my $self = shift;

    $self->reset_util;

    ok( $self->util->add_tag( 'foo' ),
        "Adding tag 'foo'"
    );

    is( $self->util->db->{taglist},
        "foo",
        "Checking tag list contains foo"
    );

    ok( ! $self->util->add_tag( 'foo' ),
        "Adding tag 'foo' that already exists"
    );

    is( $self->util->db->{taglist},
        "foo",
        "Checking tag list just just contains foo"
    );

    ok( $self->util->add_tag( 'bar' ),
        "Adding tag 'bar'"
    );

    is( $self->util->db->{taglist},
        "foo,bar",
        "Checking tag list contains foo and bar"
    );
};

test 'spam tag stats' => sub {
    my $self = shift;

    $self->reset_util;

    $self->util->store( { offer => 1, is => 1, secret => 1 }, 'spam' );
    $self->util->store( { click => 1, secret => 1, link => 1 }, 'spam' );
    $self->util->store( { secret => 1, sports => 1, link => 1 }, 'spam' );

    $self->util->store( { play => 1, sports => 1, today => 1 }, 'ham' );
    $self->util->store( { went => 1, play => 1, sports => 1 }, 'ham' );
    $self->util->store( { secret => 1, sports => 1, event => 1 }, 'ham' );
    $self->util->store( { sports => 1, is => 1, today => 1 }, 'ham' );
    $self->util->store( { sports => 1, costs => 1, money => 1 }, 'ham' );

    is_deeply( $self->util->predict_tags( { today => 1, is => 1, secret => 1 } ),
               { spam => .48576, ham => 0.51424 },
               "Getting tag suggestions"
           );
};



# todo remove document
# todo remove tags


run_me;
done_testing;
