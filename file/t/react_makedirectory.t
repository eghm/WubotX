#!/perl
use strict;
use warnings;

use File::Temp qw/ tempdir /;
use Test::More 'no_plan';

use App::Wubot::Logger;
use App::Wubot::LocalMessageStore;
use App::Wubot::Reactor::MakeDirectory;

ok( my $mkdir = App::Wubot::Reactor::MakeDirectory->new(),
    "Creating new MakeDirectory reactor object"
);

my $tempdir = tempdir( "/tmp/tmpdir-XXXXXXXXXX", CLEANUP => 1 );

ok( $mkdir->react( { dir   => "$tempdir/foo" }, { field => 'dir' } ),
    "calling react() to create directory"
);

ok( -d "$tempdir/foo",
    "Checking that directory was created"
);

ok( $mkdir->react( { dir   => "$tempdir/abc/def/ghi" }, { field => 'dir' } ),
    "calling react() to create deep directory"
);

ok( -d "$tempdir/abc/def/ghi",
    "Checking that deep directory structure was created"
);
