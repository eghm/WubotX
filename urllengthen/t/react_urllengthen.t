#!/perl
use strict;
use warnings;

no utf8;

use File::Temp qw/ tempdir /;
use Test::More;

for my $lib ( 'App::Wubot::Logger',
              'WWW::LongURL',
              'App::Wubot::Reactor::UrlLengthen',
          ) {

    eval "use $lib";
    plan skip_all => "Failed to load $lib for this test case" if $@;
}

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

ok( my $lengthener = App::Wubot::Reactor::UrlLengthen->new( { dbfile => "$tempdir/foo" } ),
    "Creating new UrlLengthen reactor object"
);

{
    my $short_url = 'http://t.co/TlEplYw2';
    my $long_url  = 'http://www.linuxinsider.com/story/73291.html';

    is( $lengthener->react( { subject => $short_url }, { field => 'subject' }  )->{subject},
        $long_url,
        "Lengthening URL for t.co"
    );

    my ( $cache ) = $lengthener->sqlite->select( { tablename => 'urls',
                                                   where     => { short_url => $short_url },
                                                   schema    => $lengthener->schema,
                                               } );

    is ( $cache->{short_url},
        $short_url,
        "Checking lookup was cached"
    );

    is ( $cache->{long_url},
        $long_url,
        "Checking lookup was cached"
    );

    is( $lengthener->react( { subject => $short_url }, { field => 'subject' }  )->{subject},
        $long_url,
        "Lengthening URL for t.co"
    );

}

{
    # this is a t.co that points to a plt.me
    my $short_url = 'http://t.co/2RbrtpVX',
    my $long_url  = 'https://plus.google.com/105487854388646525021/posts/CdZvFAh8te2';

    is( $lengthener->expand( $short_url ),
        $long_url,
        "Lengthening URL for plt.me"
    );

}

{
    # url that does not require shortening
    my $url = 'https://github.com/wu/';

    is( $lengthener->react( { subject => $url }, { field => 'subject' }  )->{subject},
        $url,
        "Lengthening URL that is not shortened"
    );

    is( $lengthener->expand( $url ),
        $url,
        "Lengthening URL that is not shortened"
    );

    is( $lengthener->react( { subject => $url }, { field => 'subject' }  )->{subject},
        $url,
        "Lengthening URL that is not shortened"
    );
}

my $test_cases = [
    { source => 'http://690.jp/5l',
      target => 'http://www.updated3news.com/',
  },
    { source => "http://plusist.com/merlyn/NDMxNzk",
      target => "https://plus.google.com/105487854388646525021/posts/FyNdMbFgiFi",
  },
];


for my $test_case ( @{ $test_cases } ) {

    is( $lengthener->expand( $test_case->{source} ),
        $test_case->{target},
        "Checking: $test_case->{source}"
    );

}

done_testing;
